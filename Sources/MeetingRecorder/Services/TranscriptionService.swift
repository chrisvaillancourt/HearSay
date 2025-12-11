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

        // Extract segments from all transcription results with proper timestamps
        let speakerLabel = source == .microphone ? "Microphone" : "System Audio"
        return results.flatMap { result in
            result.segments.map { segment in
                TranscriptSegment(
                    startTime: Double(segment.start),
                    endTime: Double(segment.end),
                    text: segment.text,
                    speakerLabel: speakerLabel
                )
            }
        }
    }
}
