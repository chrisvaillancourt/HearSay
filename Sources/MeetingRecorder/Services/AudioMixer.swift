import AVFoundation
import CoreMedia
import OSLog

/// Represents a timestamped audio buffer from a specific source
struct TimestampedAudioBuffer {
    let samples: [Float]
    let timestamp: CMTime
    let source: AudioSource
    let sampleRate: Double
}

/// Ring buffer for thread-safe audio sample storage with timestamp tracking
final class AudioRingBuffer: @unchecked Sendable {
    private var buffer: [Float]
    private var timestamps: [CMTime]
    private let capacity: Int
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private var availableFrames: Int = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
        self.timestamps = [CMTime](repeating: .zero, count: capacity)
    }

    /// Writes samples to the ring buffer
    /// - Parameters:
    ///   - samples: Audio samples to write
    ///   - startTimestamp: Starting timestamp for these samples
    /// - Returns: Number of samples actually written
    @discardableResult
    func write(_ samples: [Float], startTimestamp: CMTime) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let samplesToWrite = min(samples.count, capacity - availableFrames)
        guard samplesToWrite > 0 else { return 0 }

        for idx in 0..<samplesToWrite {
            buffer[writeIndex] = samples[idx]
            timestamps[writeIndex] = CMTimeAdd(
                startTimestamp,
                CMTimeMake(value: Int64(idx), timescale: 48000)
            )
            writeIndex = (writeIndex + 1) % capacity
        }

        availableFrames += samplesToWrite
        return samplesToWrite
    }

    /// Reads samples from the ring buffer
    /// - Parameter count: Maximum number of samples to read
    /// - Returns: Tuple of samples and their starting timestamp, or nil if buffer is empty
    func read(_ count: Int) -> (samples: [Float], timestamp: CMTime)? {
        lock.lock()
        defer { lock.unlock() }

        guard availableFrames > 0 else { return nil }

        let samplesToRead = min(count, availableFrames)
        var samples = [Float](repeating: 0, count: samplesToRead)
        let startTimestamp = timestamps[readIndex]

        for idx in 0..<samplesToRead {
            samples[idx] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }

        availableFrames -= samplesToRead
        return (samples, startTimestamp)
    }

    /// Returns the current number of available samples
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return availableFrames
    }

    /// Returns the earliest timestamp in the buffer, or nil if empty
    var earliestTimestamp: CMTime? {
        lock.lock()
        defer { lock.unlock() }
        guard availableFrames > 0 else { return nil }
        return timestamps[readIndex]
    }

    /// Clears all samples from the buffer
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        readIndex = 0
        availableFrames = 0
    }
}

/// Handles mixing of system audio and microphone audio into a synchronized stereo stream
/// Left channel = System audio, Right channel = Microphone
actor AudioMixer {
    private let logger = Logger(subsystem: "com.meetingrecorder", category: "AudioMixer")

    // Ring buffers for each audio source
    private let systemBuffer: AudioRingBuffer
    private let microphoneBuffer: AudioRingBuffer

    // Buffer configuration
    private let bufferCapacity: Int
    private let targetSampleRate: Double = 48000.0  // Common sample rate for mixing
    private let mixChunkSize: Int = 4800  // 100ms at 48kHz

    // Clock alignment
    private var systemClockOffset: CMTime = .zero
    private var microphoneClockOffset: CMTime = .zero
    private var isAligned = false
    private var alignmentReferenceTime: CMTime = .zero

    // Mixed output callback
    private var mixedOutputHandler: (([Float], [Float], CMTime) async -> Void)?

    // State tracking
    private var systemStartTime: CMTime?
    private var microphoneStartTime: CMTime?
    private var lastMixTime: CMTime = .zero

    init(bufferDurationSeconds: Double = 5.0) {
        // Buffer capacity for 5 seconds of audio at 48kHz
        self.bufferCapacity = Int(bufferDurationSeconds * targetSampleRate)
        self.systemBuffer = AudioRingBuffer(capacity: bufferCapacity)
        self.microphoneBuffer = AudioRingBuffer(capacity: bufferCapacity)
    }

    /// Sets the handler for mixed stereo output
    /// - Parameter handler: Closure receiving (leftChannel, rightChannel, timestamp)
    func setMixedOutputHandler(_ handler: @escaping ([Float], [Float], CMTime) async -> Void) {
        self.mixedOutputHandler = handler
    }

    /// Receives audio from a source and adds it to the appropriate ring buffer
    /// - Parameter buffer: Timestamped audio buffer from either system or microphone
    func receive(buffer: TimestampedAudioBuffer) async {
        // Resample to target rate if needed
        let resampled = resampleIfNeeded(buffer)

        switch buffer.source {
        case .system:
            handleSystemAudio(resampled)
        case .microphone:
            handleMicrophoneAudio(resampled)
        case .mixed:
            // Mixed audio is output only, not an input source
            logger.warning("Received mixed audio as input; this should not happen")
        }

        // Check if we should perform clock alignment
        if !isAligned {
            attemptClockAlignment()
        }

        // Try to produce mixed output
        await produceMixedOutput()
    }

    /// Resets the mixer state
    func reset() {
        systemBuffer.reset()
        microphoneBuffer.reset()
        isAligned = false
        systemStartTime = nil
        microphoneStartTime = nil
        systemClockOffset = .zero
        microphoneClockOffset = .zero
        lastMixTime = .zero
        logger.info("AudioMixer reset")
    }

    // MARK: - Private Methods

    private func handleSystemAudio(_ buffer: TimestampedAudioBuffer) {
        if systemStartTime == nil {
            systemStartTime = buffer.timestamp
            logger.info("System audio stream started at \(buffer.timestamp.seconds)s")
        }

        let adjustedTimestamp = CMTimeSubtract(buffer.timestamp, systemClockOffset)
        systemBuffer.write(buffer.samples, startTimestamp: adjustedTimestamp)
    }

    private func handleMicrophoneAudio(_ buffer: TimestampedAudioBuffer) {
        if microphoneStartTime == nil {
            microphoneStartTime = buffer.timestamp
            logger.info("Microphone audio stream started at \(buffer.timestamp.seconds)s")
        }

        let adjustedTimestamp = CMTimeSubtract(buffer.timestamp, microphoneClockOffset)
        microphoneBuffer.write(buffer.samples, startTimestamp: adjustedTimestamp)
    }

    /// Attempts to align the clocks of both audio sources
    private func attemptClockAlignment() {
        guard let sysStart = systemStartTime,
            let micStart = microphoneStartTime
        else {
            return
        }

        // Use the later start time as reference
        if CMTimeCompare(sysStart, micStart) < 0 {
            // Microphone started later - align system to microphone
            alignmentReferenceTime = micStart
            systemClockOffset = CMTimeSubtract(sysStart, micStart)
            microphoneClockOffset = .zero
        } else {
            // System started later or at same time - align microphone to system
            alignmentReferenceTime = sysStart
            microphoneClockOffset = CMTimeSubtract(micStart, sysStart)
            systemClockOffset = .zero
        }

        isAligned = true
        logger.info(
            """
            Clock alignment complete - Reference: \(self.alignmentReferenceTime.seconds)s, \
            System offset: \(self.systemClockOffset.seconds)s, \
            Mic offset: \(self.microphoneClockOffset.seconds)s
            """
        )
    }

    /// Produces mixed stereo output when both buffers have sufficient data
    private func produceMixedOutput() async {
        guard isAligned else { return }

        // Check if both buffers have enough data
        let systemAvailable = systemBuffer.count
        let micAvailable = microphoneBuffer.count

        guard systemAvailable >= mixChunkSize || micAvailable >= mixChunkSize else {
            return
        }

        // Determine how many samples we can mix
        let samplesToMix = min(
            max(systemAvailable, micAvailable),
            mixChunkSize
        )

        // Read from both buffers, padding with silence if one is behind
        let systemData = systemBuffer.read(samplesToMix)
        let micData = microphoneBuffer.read(samplesToMix)

        // Create stereo output: Left = System, Right = Microphone
        var leftChannel: [Float]
        var rightChannel: [Float]
        var outputTimestamp: CMTime

        if let sysData = systemData {
            leftChannel = sysData.samples
            outputTimestamp = sysData.timestamp
            // Pad to match size if needed
            if leftChannel.count < samplesToMix {
                leftChannel.append(contentsOf: [Float](repeating: 0, count: samplesToMix - leftChannel.count))
            }
        } else {
            leftChannel = [Float](repeating: 0, count: samplesToMix)
            outputTimestamp = lastMixTime
        }

        if let micData = micData {
            rightChannel = micData.samples
            // Use mic timestamp if system wasn't available
            if systemData == nil {
                outputTimestamp = micData.timestamp
            }
            // Pad to match size if needed
            if rightChannel.count < samplesToMix {
                rightChannel.append(contentsOf: [Float](repeating: 0, count: samplesToMix - rightChannel.count))
            }
        } else {
            rightChannel = [Float](repeating: 0, count: samplesToMix)
        }

        // Update last mix time
        lastMixTime = CMTimeAdd(
            outputTimestamp,
            CMTimeMake(value: Int64(samplesToMix), timescale: Int32(targetSampleRate))
        )

        // Send to handler
        await mixedOutputHandler?(leftChannel, rightChannel, outputTimestamp)
    }

    /// Resamples audio to the target sample rate if necessary
    private func resampleIfNeeded(_ buffer: TimestampedAudioBuffer) -> TimestampedAudioBuffer {
        guard abs(buffer.sampleRate - targetSampleRate) > 1.0 else {
            return buffer
        }

        let ratio = targetSampleRate / buffer.sampleRate
        let outputLength = Int(Double(buffer.samples.count) * ratio)

        guard outputLength > 0 else {
            return buffer
        }

        var resampled = [Float](repeating: 0, count: outputLength)

        // Linear interpolation resampling
        for idx in 0..<outputLength {
            let sourceIndex = Double(idx) / ratio
            let lowerIndex = Int(sourceIndex)
            let upperIndex = min(lowerIndex + 1, buffer.samples.count - 1)
            let fraction = Float(sourceIndex - Double(lowerIndex))

            if lowerIndex < buffer.samples.count {
                let lower = buffer.samples[lowerIndex]
                let upper = buffer.samples[upperIndex]
                resampled[idx] = lower + fraction * (upper - lower)
            }
        }

        return TimestampedAudioBuffer(
            samples: resampled,
            timestamp: buffer.timestamp,
            source: buffer.source,
            sampleRate: targetSampleRate
        )
    }

    // MARK: - Diagnostic Methods

    /// Returns current buffer levels for diagnostics
    func getBufferLevels() -> (system: Int, microphone: Int) {
        (systemBuffer.count, microphoneBuffer.count)
    }

    /// Returns whether clock alignment has been achieved
    func isClockAligned() -> Bool {
        isAligned
    }
}
