import CoreML
import Foundation
@preconcurrency import WhisperKit

actor TranscriptionService {
    private var whisperKit: WhisperKit?
    private var isInitialized = false

    func initialize() async throws {
        guard !isInitialized else { return }

        // Initialize WhisperKit with default settings which downloads recommended model
        // or use a specific one if needed.
        // Note: This might download the model on first run.
        whisperKit = try await WhisperKit(verbose: true)
        isInitialized = true
    }

    func transcribe(audioSamples: [Float], source: AudioSource) async throws -> [TranscriptSegment] {
        guard let whisperKit = whisperKit else {
            throw NSError(
                domain: "TranscriptionService", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "WhisperKit not initialized"])
        }

        let results = try await whisperKit.transcribe(audioArray: audioSamples)
        
        // Create transcript segments with source tracking for diarization
        // For now, create a simple segment with the full transcription text
        // TODO: Enhance with proper timing when WhisperKit API is clarified
        return results.map { result in
            TranscriptSegment(
                startTime: 0.0,
                endTime: Double(audioSamples.count) / 16000.0, // Approximate duration
                text: result.text,
                speakerLabel: source == .microphone ? "Microphone" : "System Audio"
            )
        }
    }
}