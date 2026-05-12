import Foundation
import OSLog
@preconcurrency import WhisperKit

/// Configuration for Voice Activity Detection
struct VADConfiguration: Sendable {
    /// Sample rate of the audio (WhisperKit expects 16kHz)
    let sampleRate: Int

    /// Length of each analysis frame in seconds
    let frameLength: Float

    /// Frame overlap in seconds to catch audio at chunk boundaries
    let frameOverlap: Float

    /// Energy threshold for voice detection (samples below this are considered silence)
    /// Lower values are more sensitive to quiet speech, higher values filter out more background noise
    let energyThreshold: Float

    /// Minimum ratio of voice-active frames required to consider a chunk as containing speech
    /// 0.0 = any voice activity triggers transcription, 1.0 = entire chunk must have voice
    let minimumVoiceRatio: Float

    static let `default` = VADConfiguration(
        sampleRate: 16000,
        frameLength: 0.1,  // 100ms frames
        frameOverlap: 0.0,
        energyThreshold: 0.02,  // WhisperKit's default
        minimumVoiceRatio: 0.05  // At least 5% voice activity to transcribe
    )

    /// More sensitive configuration for quiet environments
    static let sensitive = VADConfiguration(
        sampleRate: 16000,
        frameLength: 0.1,
        frameOverlap: 0.02,
        energyThreshold: 0.01,
        minimumVoiceRatio: 0.02
    )

    /// Less sensitive configuration for noisy environments
    static let robust = VADConfiguration(
        sampleRate: 16000,
        frameLength: 0.1,
        frameOverlap: 0.0,
        energyThreshold: 0.04,
        minimumVoiceRatio: 0.1
    )
}

/// Aggregated voice-activity statistics across a session
struct VADStatistics: Sendable {
    let totalAnalyzed: Int
    let withVoice: Int
    let skipped: Int
}

/// Result of voice activity detection analysis
struct VADResult: Sendable {
    /// Whether voice activity was detected
    let hasVoiceActivity: Bool

    /// Ratio of frames containing voice activity (0.0 to 1.0)
    let voiceActivityRatio: Float

    /// Number of frames analyzed
    let totalFrames: Int

    /// Number of frames with detected voice activity
    let voiceFrames: Int

    /// Average energy level of the audio chunk
    let averageEnergy: Float
}

/// Service for detecting voice activity in audio samples
/// Uses WhisperKit's EnergyVAD for energy-based voice activity detection
actor VoiceActivityService {
    private let configuration: VADConfiguration
    private let vad: EnergyVAD
    private let logger = Logger(subsystem: "com.meetingrecorder", category: "VoiceActivityService")

    // Statistics tracking
    private var totalChunksAnalyzed: Int = 0
    private var chunksWithVoice: Int = 0
    private var chunksSkipped: Int = 0

    init(configuration: VADConfiguration = .default) {
        self.configuration = configuration
        self.vad = EnergyVAD(
            sampleRate: configuration.sampleRate,
            frameLength: configuration.frameLength,
            frameOverlap: configuration.frameOverlap,
            energyThreshold: configuration.energyThreshold
        )
    }

    /// Analyzes audio samples for voice activity
    /// - Parameter audioSamples: Array of Float audio samples at 16kHz
    /// - Returns: VADResult containing detection results
    func analyzeVoiceActivity(in audioSamples: [Float]) -> VADResult {
        guard !audioSamples.isEmpty else {
            return VADResult(
                hasVoiceActivity: false,
                voiceActivityRatio: 0.0,
                totalFrames: 0,
                voiceFrames: 0,
                averageEnergy: 0.0
            )
        }

        // Get per-frame voice activity detection
        let voiceActivity = vad.voiceActivity(in: audioSamples)

        let totalFrames = voiceActivity.count
        let voiceFrames = voiceActivity.filter { $0 }.count
        let voiceRatio = totalFrames > 0 ? Float(voiceFrames) / Float(totalFrames) : 0.0

        // Calculate average energy using WhisperKit's utility
        let averageEnergy = calculateAverageEnergy(of: audioSamples)

        let hasVoice = voiceRatio >= configuration.minimumVoiceRatio

        // Update statistics
        totalChunksAnalyzed += 1
        if hasVoice {
            chunksWithVoice += 1
        } else {
            chunksSkipped += 1
        }

        return VADResult(
            hasVoiceActivity: hasVoice,
            voiceActivityRatio: voiceRatio,
            totalFrames: totalFrames,
            voiceFrames: voiceFrames,
            averageEnergy: averageEnergy
        )
    }

    /// Checks if audio samples contain voice activity
    /// - Parameter audioSamples: Array of Float audio samples at 16kHz
    /// - Returns: true if voice activity is detected, false otherwise
    func hasVoiceActivity(in audioSamples: [Float]) -> Bool {
        analyzeVoiceActivity(in: audioSamples).hasVoiceActivity
    }

    /// Extracts only the portions of audio that contain voice activity
    /// - Parameter audioSamples: Array of Float audio samples at 16kHz
    /// - Returns: Array of audio chunks containing voice activity with their start indices
    func extractVoiceSegments(from audioSamples: [Float]) -> [(startIndex: Int, samples: [Float])] {
        let activeChunks = vad.calculateActiveChunks(in: audioSamples)

        return activeChunks.map { chunk in
            let samples = Array(audioSamples[chunk.startIndex..<min(chunk.endIndex, audioSamples.count)])
            return (startIndex: chunk.startIndex, samples: samples)
        }
    }

    /// Returns current VAD statistics
    func getStatistics() -> VADStatistics {
        VADStatistics(
            totalAnalyzed: totalChunksAnalyzed,
            withVoice: chunksWithVoice,
            skipped: chunksSkipped
        )
    }

    /// Resets the statistics counters
    func resetStatistics() {
        totalChunksAnalyzed = 0
        chunksWithVoice = 0
        chunksSkipped = 0
        logger.info("VAD statistics reset")
    }

    /// Logs current statistics
    func logStatistics() {
        let skipRate =
            totalChunksAnalyzed > 0
            ? Float(chunksSkipped) / Float(totalChunksAnalyzed) * 100
            : 0
        logger.info(
            """
            VAD Statistics - Total: \(self.totalChunksAnalyzed), \
            With Voice: \(self.chunksWithVoice), \
            Skipped: \(self.chunksSkipped) (\(String(format: "%.1f", skipRate))%)
            """
        )
    }

    // MARK: - Private Helpers

    /// Calculate RMS energy of audio samples
    private func calculateAverageEnergy(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }

        var sumOfSquares: Float = 0.0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}
