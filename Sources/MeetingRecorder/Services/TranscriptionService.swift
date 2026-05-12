import CoreML
import Foundation
import OSLog
@preconcurrency import WhisperKit

actor TranscriptionService {
    private var whisperKit: WhisperKit?
    private var isInitialized = false
    private let logger = Logger(subsystem: "com.meetingrecorder", category: "TranscriptionService")

    /// Default decoding options with VAD-based chunking for efficient processing
    private let decodingOptions: DecodingOptions

    init() {
        // Configure decoding options to use VAD-based chunking
        // This allows WhisperKit to skip silent portions within chunks
        self.decodingOptions = DecodingOptions(
            verbose: false,
            task: .transcribe,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: false,
            chunkingStrategy: .vad  // Enable VAD-based chunking for efficient processing
        )
    }

    func initialize() async throws {
        guard !isInitialized else { return }

        // Initialize WhisperKit with EnergyVAD for voice activity detection
        let config = WhisperKitConfig(
            voiceActivityDetector: EnergyVAD(),  // Use energy-based VAD
            verbose: true
        )

        // Note: This might download the model on first run.
        whisperKit = try await WhisperKit(config)
        isInitialized = true
        logger.info("WhisperKit initialized with VAD support")
    }

    /// Transcribes audio samples and returns segments with session-relative timestamps.
    /// - Parameters:
    ///   - audioSamples: Float array of audio samples at 16kHz
    ///   - source: The audio source for speaker labeling
    ///   - sessionTimeOffset: Time offset from session start (in seconds). Added to WhisperKit's
    ///                        relative timestamps to produce absolute session timestamps.
    /// - Returns: Array of TranscriptSegments with timestamps relative to session start
    func transcribe(
        audioSamples: [Float],
        source: AudioSource,
        sessionTimeOffset: TimeInterval = 0.0
    ) async throws -> [TranscriptSegment] {
        guard let whisperKit = whisperKit else {
            throw NSError(
                domain: "TranscriptionService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "WhisperKit not initialized"]
            )
        }

        // Use decoding options with VAD-based chunking
        let results = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: decodingOptions
        )

        // Extract segments from all transcription results with proper timestamps
        let speakerLabel: String
        switch source {
        case .microphone:
            speakerLabel = "Microphone"
        case .system:
            speakerLabel = "System Audio"
        case .mixed:
            speakerLabel = "Mixed Audio"
        }

        // Apply session time offset to convert WhisperKit's chunk-relative timestamps
        // to session-relative timestamps that can be correlated with the video timeline
        return results.flatMap { result in
            result.segments.map { segment in
                TranscriptSegment(
                    startTime: Double(segment.start) + sessionTimeOffset,
                    endTime: Double(segment.end) + sessionTimeOffset,
                    text: segment.text,
                    speakerLabel: speakerLabel
                )
            }
        }
    }
}
