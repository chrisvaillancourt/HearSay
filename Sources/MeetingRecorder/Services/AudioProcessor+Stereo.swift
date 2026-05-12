import CoreMedia
import Foundation

// MARK: - Stereo Processing (AudioMixer Integration)

extension AudioProcessor {
    /// Processes mixed stereo audio from the AudioMixer.
    /// Left channel contains system audio, right channel contains microphone audio.
    /// - Parameters:
    ///   - leftChannel: System audio samples (at mixer sample rate, typically 48kHz)
    ///   - rightChannel: Microphone audio samples (at mixer sample rate, typically 48kHz)
    ///   - timestamp: Presentation timestamp for this audio chunk
    func processMixedStereo(leftChannel: [Float], rightChannel: [Float], timestamp: CMTime) async {
        if stereoSessionStartTime == nil {
            stereoSessionStartTime = timestamp
            logger.info("Stereo session started at timestamp: \(timestamp.seconds)s")
        }

        let sessionTimeOffset: TimeInterval
        if let startTime = stereoSessionStartTime {
            sessionTimeOffset = CMTimeGetSeconds(CMTimeSubtract(timestamp, startTime))
        } else {
            sessionTimeOffset = 0.0
        }

        // Resample both channels from mixer rate (48kHz) to target rate (16kHz) for WhisperKit
        let resampledSystem = resampleToTargetRate(leftChannel, fromRate: mixerSampleRate)
        let resampledMic = resampleToTargetRate(rightChannel, fromRate: mixerSampleRate)

        systemAudioBuffer.append(contentsOf: resampledSystem)
        microphoneAudioBuffer.append(contentsOf: resampledMic)

        enforceStereoBufferLimits()
        lastProcessedStereoTimestamp = timestamp

        await processStereoBuffersIfReady(sessionTimeOffset: sessionTimeOffset)
    }

    /// Returns the current stereo buffer sizes for diagnostics
    func getStereoBufferSizes() -> (system: Int, microphone: Int) {
        (systemAudioBuffer.count, microphoneAudioBuffer.count)
    }

    /// Enforces maximum buffer size limits for stereo buffers
    func enforceStereoBufferLimits() {
        if systemAudioBuffer.count > maxBufferSize {
            let excess = systemAudioBuffer.count - maxBufferSize
            systemAudioBuffer.removeFirst(excess)
            logger.warning("System audio buffer exceeded limit, dropped \(excess) samples")
        }
        if microphoneAudioBuffer.count > maxBufferSize {
            let excess = microphoneAudioBuffer.count - maxBufferSize
            microphoneAudioBuffer.removeFirst(excess)
            logger.warning("Microphone audio buffer exceeded limit, dropped \(excess) samples")
        }
    }

    /// Processes stereo buffers when both have enough data
    func processStereoBuffersIfReady(sessionTimeOffset: TimeInterval) async {
        var currentOffset = sessionTimeOffset

        while systemAudioBuffer.count >= bufferSizeThreshold
            && microphoneAudioBuffer.count >= bufferSizeThreshold {
            let systemChunk = Array(systemAudioBuffer.prefix(bufferSizeThreshold))
            let micChunk = Array(microphoneAudioBuffer.prefix(bufferSizeThreshold))

            systemAudioBuffer.removeFirst(bufferSizeThreshold)
            microphoneAudioBuffer.removeFirst(bufferSizeThreshold)

            await transcribeStereoChunk(
                systemChannel: systemChunk,
                microphoneChannel: micChunk,
                sessionTimeOffset: currentOffset
            )

            let chunkDuration = Double(bufferSizeThreshold) / targetSampleRate
            currentOffset += chunkDuration
        }
    }

    /// Transcribes both stereo channels and merges results
    func transcribeStereoChunk(
        systemChannel: [Float],
        microphoneChannel: [Float],
        sessionTimeOffset: TimeInterval
    ) async {
        let systemSegments = await transcribeChannelWithVAD(
            systemChannel,
            source: .system,
            speakerLabel: "System Audio",
            sessionTimeOffset: sessionTimeOffset
        )

        let micSegments = await transcribeChannelWithVAD(
            microphoneChannel,
            source: .microphone,
            speakerLabel: "Microphone",
            sessionTimeOffset: sessionTimeOffset
        )

        var allSegments = systemSegments + micSegments
        allSegments.sort { $0.startTime < $1.startTime }

        if !allSegments.isEmpty {
            logger.info(
                """
                Stereo transcription completed: \(systemSegments.count) system segments, \
                \(micSegments.count) mic segments at offset \(String(format: "%.2f", sessionTimeOffset))s
                """
            )
            segmentHandler?(allSegments)
        }
    }

    /// Transcribes a single channel with VAD check
    func transcribeChannelWithVAD(
        _ samples: [Float],
        source: AudioSource,
        speakerLabel: String,
        sessionTimeOffset: TimeInterval
    ) async -> [TranscriptSegment] {
        totalChunksProcessed += 1

        if vadEnabled {
            let vadResult = await voiceActivityService.analyzeVoiceActivity(in: samples)

            if !vadResult.hasVoiceActivity {
                chunksSkippedByVAD += 1
                logger.debug(
                    """
                    Skipping silent \(speakerLabel) channel - \
                    Voice ratio: \(String(format: "%.2f", vadResult.voiceActivityRatio)), \
                    Energy: \(String(format: "%.4f", vadResult.averageEnergy))
                    """
                )
                return []
            }
        }

        do {
            guard
                let segments = try await transcriptionService?.transcribe(
                    audioSamples: samples,
                    source: source,
                    sessionTimeOffset: sessionTimeOffset
                )
            else {
                return []
            }
            return segments
        } catch {
            logger.error("Transcription error for \(speakerLabel): \(error.localizedDescription)")
            errorHandler?(error)
            return []
        }
    }

    /// Resamples audio samples to the target sample rate using linear interpolation
    func resampleToTargetRate(_ samples: [Float], fromRate: Double) -> [Float] {
        guard abs(fromRate - targetSampleRate) > 1.0 else {
            return samples
        }

        let ratio = targetSampleRate / fromRate
        let outputLength = Int(Double(samples.count) * ratio)

        guard outputLength > 0 else { return samples }

        var resampled = [Float](repeating: 0, count: outputLength)

        for samIdx in 0..<outputLength where samIdx < samples.count {
            let sourceIndex = Double(samIdx) / ratio
            let lowerIndex = Int(sourceIndex)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(sourceIndex - Double(lowerIndex))

            if lowerIndex < samples.count {
                let lower = samples[lowerIndex]
                let upper = samples[upperIndex]
                resampled[samIdx] = lower + fraction * (upper - lower)
            }
        }

        return resampled
    }
}
