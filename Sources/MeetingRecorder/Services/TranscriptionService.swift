import Foundation
@preconcurrency import WhisperKit
import CoreML

actor TranscriptionService {
    private var whisperKit: WhisperKit?
    private var isInitialized = false
    
    func initialize() async throws {
        guard !isInitialized else { return }
        
        // Initialize WhisperKit with default settings which downloads the recommended model
        // or use a specific one if needed.
        // Note: This might download the model on first run.
        whisperKit = try await WhisperKit(verbose: true)
        isInitialized = true
    }
    
    func transcribe(audioSamples: [Float]) async throws -> [TranscriptionResult] {
        guard let whisperKit = whisperKit else {
            throw NSError(domain: "TranscriptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "WhisperKit not initialized"])
        }
        
        let results = try await whisperKit.transcribe(audioArray: audioSamples)
        return results
    }
}

// Helper struct to map WhisperKit results if needed, though WhisperKit likely returns its own types.
// We will map them to our Model types in the calling layer.
