import CoreMedia
import OSLog
@preconcurrency import WhisperKit

enum AudioSource {
    case microphone
    case system
    case mixed  // Combined stereo: L=System, R=Microphone
}

/// Aggregated VAD statistics for the current session
struct AudioProcessorVADStatistics: Sendable {
    let totalChunks: Int
    let skippedChunks: Int
    let skipPercentage: Float
}

/// Represents a chunk of audio samples with its timestamp offset within the session
struct TimestampedAudioChunk {
    let samples: [Float]
    let sessionTimeOffset: TimeInterval  // Offset from session start in seconds
    let source: AudioSource
}

actor AudioProcessor {
    // Configuration
    let targetSampleRate: Double = 16000.0  // WhisperKit expects 16kHz
    let mixerSampleRate: Double = 48000.0  // AudioMixer outputs at 48kHz
    let logger = Logger(subsystem: "com.meetingrecorder", category: "AudioProcessor")

    // Buffer management for legacy single-source processing
    private var audioBuffer: [Float] = []
    let bufferSizeThreshold = 16000 * 30  // Process every 30 seconds of audio
    let maxBufferSize = 16000 * 60 * 5  // Maximum 5 minutes to prevent unbounded growth

    // Buffer management for stereo mixed audio
    var systemAudioBuffer: [Float] = []  // Left channel (System)
    var microphoneAudioBuffer: [Float] = []  // Right channel (Microphone)

    // Timestamp tracking
    private var sessionTimestamp: SessionTimestamp?
    /// The session time offset of the first sample currently in the buffer
    private var bufferStartTimeOffset: TimeInterval = 0.0
    /// Track whether we've set the initial buffer offset
    private var hasInitialBufferOffset = false

    // Stereo session timestamp tracking
    var stereoSessionStartTime: CMTime?
    var lastProcessedStereoTimestamp: CMTime = .zero

    // Voice Activity Detection
    let voiceActivityService: VoiceActivityService
    var vadEnabled: Bool = true

    // VAD Statistics
    var totalChunksProcessed: Int = 0
    var chunksSkippedByVAD: Int = 0

    // Error handling
    var errorHandler: ((Error) -> Void)?

    // Segment persistence handler
    var segmentHandler: (([TranscriptSegment]) -> Void)?

    var transcriptionService: TranscriptionService?

    init(vadConfiguration: VADConfiguration = .default) {
        self.voiceActivityService = VoiceActivityService(configuration: vadConfiguration)
    }

    func setTranscriptionService(_ service: TranscriptionService) {
        self.transcriptionService = service
    }

    func setSessionTimestamp(_ timestamp: SessionTimestamp) {
        self.sessionTimestamp = timestamp
    }

    func setErrorHandler(_ handler: @escaping (any Error) -> Void) {
        self.errorHandler = handler
    }

    func setSegmentHandler(_ handler: @escaping ([TranscriptSegment]) -> Void) {
        self.segmentHandler = handler
    }

    /// Enables or disables Voice Activity Detection
    /// When enabled, silent audio chunks are skipped to save compute resources
    func setVADEnabled(_ enabled: Bool) {
        self.vadEnabled = enabled
        logger.info("VAD \(enabled ? "enabled" : "disabled")")
    }

    /// Returns whether VAD is currently enabled
    func isVADEnabled() -> Bool {
        vadEnabled
    }

    func reset() async {
        audioBuffer.removeAll()
        systemAudioBuffer.removeAll()
        microphoneAudioBuffer.removeAll()
        bufferStartTimeOffset = 0.0
        hasInitialBufferOffset = false
        stereoSessionStartTime = nil
        lastProcessedStereoTimestamp = .zero
        totalChunksProcessed = 0
        chunksSkippedByVAD = 0
        await voiceActivityService.resetStatistics()
        logger.info("AudioProcessor buffer reset")
    }

    /// Returns VAD statistics for the current session
    func getVADStatistics() -> AudioProcessorVADStatistics {
        let percentage =
            totalChunksProcessed > 0
            ? Float(chunksSkippedByVAD) / Float(totalChunksProcessed) * 100
            : 0
        return AudioProcessorVADStatistics(
            totalChunks: totalChunksProcessed,
            skippedChunks: chunksSkippedByVAD,
            skipPercentage: percentage
        )
    }

    /// Logs current VAD statistics
    func logVADStatistics() {
        let stats = getVADStatistics()
        logger.info(
            """
            VAD Statistics - Total chunks: \(stats.totalChunks), \
            Skipped: \(stats.skippedChunks) (\(String(format: "%.1f", stats.skipPercentage))%)
            """
        )
    }

    /// Processes audio samples for transcription with timestamp tracking.
    /// - Parameters:
    ///   - audioSamples: The audio samples to process
    ///   - source: The audio source (microphone or system)
    ///   - sampleRate: The actual sample rate of the audio. If nil, falls back to default values based on source.
    ///   - presentationTime: The CMTime presentation timestamp from the sample buffer.
    ///                       Used to calculate accurate segment timestamps relative to session start.
    func process(
        audioSamples: [Float],
        source: AudioSource,
        sampleRate: Double? = nil,
        presentationTime: CMTime? = nil
    ) async {
        do {
            // Record timestamp and get session-relative offset
            if let presentationTime = presentationTime,
                let sessionTimestamp = sessionTimestamp {
                if let offset = await sessionTimestamp.recordTimestamp(presentationTime) {
                    // Set initial buffer offset on first samples
                    if !hasInitialBufferOffset {
                        bufferStartTimeOffset = offset
                        hasInitialBufferOffset = true
                        logger.info("Initial buffer offset set to \(offset)s")
                    }
                }
            }

            // Resample audio to 16kHz if needed
            let resampledSamples = try await resampleAudio(audioSamples, source: source, inputSampleRate: sampleRate)

            // Add to buffer with size limit check
            audioBuffer.append(contentsOf: resampledSamples)

            // Prevent unbounded growth
            if audioBuffer.count > maxBufferSize {
                let excessCount = audioBuffer.count - maxBufferSize
                audioBuffer.removeFirst(excessCount)
                // Adjust buffer start offset when dropping samples
                let droppedDuration = Double(excessCount) / targetSampleRate
                bufferStartTimeOffset += droppedDuration
                logger.warning("Audio buffer exceeded maximum size, dropped \(excessCount) samples")
            }

            // Check if we have enough data to transcribe
            while audioBuffer.count >= bufferSizeThreshold {
                let chunkToProcess = Array(audioBuffer.prefix(bufferSizeThreshold))
                // Calculate the time offset for this chunk before removing from buffer
                let chunkTimeOffset = bufferStartTimeOffset
                audioBuffer.removeFirst(bufferSizeThreshold)

                // Update buffer start offset for next chunk
                // Each chunk is bufferSizeThreshold samples at targetSampleRate
                let chunkDuration = Double(bufferSizeThreshold) / targetSampleRate
                bufferStartTimeOffset += chunkDuration

                await transcribeChunk(chunkToProcess, source: source, sessionTimeOffset: chunkTimeOffset)
            }
        } catch {
            logger.error("Audio processing error: \(error.localizedDescription)")
            errorHandler?(error)
        }
    }

    private func resampleAudio(
        _ samples: [Float],
        source: AudioSource,
        inputSampleRate providedSampleRate: Double?
    ) async throws -> [Float] {
        // Use provided sample rate or fall back to default detection
        let inputSampleRate = providedSampleRate ?? detectSampleRate(for: source)

        if providedSampleRate == nil {
            logger.warning(
                """
                Sample rate not provided for \(String(describing: source)) audio, \
                using fallback rate: \(inputSampleRate)Hz
                """
            )
        }

        // If already at target rate, no conversion needed
        if abs(inputSampleRate - self.targetSampleRate) < 1.0 {
            logger.info("Audio from \(String(describing: source)) already at target rate (\(inputSampleRate)Hz)")
            return samples
        }

        // Use linear interpolation resampling to avoid AVAudioConverter complexity
        let ratio = self.targetSampleRate / inputSampleRate
        let outputLength = Int(Double(samples.count) * ratio)

        guard outputLength > 0 else {
            logger.warning("Resampling would result in empty output, returning original samples")
            return samples
        }

        var resampledSamples: [Float] = []
        resampledSamples.reserveCapacity(outputLength)

        for idx in 0..<outputLength {
            let sourceIndex = Double(idx) / ratio
            let lowerIndex = Int(sourceIndex)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = sourceIndex - Double(lowerIndex)

            if lowerIndex < samples.count {
                let lowerSample = samples[lowerIndex]
                let upperSample = samples[upperIndex]
                let interpolatedSample = lowerSample + Float(fraction) * (upperSample - lowerSample)
                resampledSamples.append(interpolatedSample)
            }
        }

        logger.info(
            """
            Successfully resampled \(samples.count) samples from \(inputSampleRate)Hz to \
            \(self.targetSampleRate)Hz using linear interpolation (\(resampledSamples.count) samples)
            """
        )

        return resampledSamples
    }

    /// Returns a fallback sample rate for the given audio source.
    /// This is used only when the actual sample rate cannot be extracted from the CMSampleBuffer.
    /// - Parameter source: The audio source
    /// - Returns: A default sample rate based on typical values for the source type
    private func detectSampleRate(for source: AudioSource) -> Double {
        switch source {
        case .microphone:
            // Fallback: Microphone typically captures at 44.1kHz or 48kHz
            // Using 44.1kHz as it's most common for built-in mics
            return 44100.0
        case .system:
            // Fallback: ScreenCaptureKit typically captures at 48kHz
            return 48000.0
        case .mixed:
            // Fallback: Mixed audio from AudioMixer is normalized to 48kHz
            return 48000.0
        }
    }

    /// Transcribes an audio chunk with session-relative timestamp offset.
    /// - Parameters:
    ///   - chunk: The audio samples to transcribe
    ///   - source: The audio source for speaker labeling
    ///   - sessionTimeOffset: The time offset from session start for this chunk (in seconds).
    ///                        WhisperKit segment timestamps are added to this offset.
    private func transcribeChunk(_ chunk: [Float], source: AudioSource, sessionTimeOffset: TimeInterval = 0.0) async {
        totalChunksProcessed += 1

        // Check for voice activity before transcription if VAD is enabled
        if vadEnabled {
            let vadResult = await voiceActivityService.analyzeVoiceActivity(in: chunk)

            if !vadResult.hasVoiceActivity {
                chunksSkippedByVAD += 1
                logger.info(
                    """
                    Skipping silent chunk for \(String(describing: source)) audio - \
                    Voice ratio: \(String(format: "%.2f", vadResult.voiceActivityRatio)), \
                    Energy: \(String(format: "%.4f", vadResult.averageEnergy))
                    """
                )
                return
            }

            logger.info(
                """
                Voice activity detected for \(String(describing: source)) audio - \
                Voice ratio: \(String(format: "%.2f", vadResult.voiceActivityRatio)), \
                Frames: \(vadResult.voiceFrames)/\(vadResult.totalFrames)
                """
            )
        }

        do {
            guard
                let segments = try await transcriptionService?.transcribe(
                    audioSamples: chunk,
                    source: source,
                    sessionTimeOffset: sessionTimeOffset
                )
            else {
                return
            }

            logger.info(
                """
                Transcription completed for \(String(describing: source)) audio: \
                \(segments.count) segments at offset \(String(format: "%.2f", sessionTimeOffset))s
                """
            )

            // Persist segments via handler if available
            if !segments.isEmpty {
                segmentHandler?(segments)
            }
        } catch {
            logger.error("Transcription error for \(String(describing: source)) audio: \(error.localizedDescription)")
            errorHandler?(error)
        }
    }

    // MARK: - Buffer Management

    func getBufferSize() -> Int {
        audioBuffer.count
    }
}
