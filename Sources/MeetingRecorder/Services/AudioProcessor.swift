import AVFoundation
import CoreMedia
import OSLog

enum AudioSource {
    case microphone
    case system
}

actor AudioProcessor {
    // Configuration
    private let sampleRate: Double = 16000.0  // Whisper usually likes 16kHz
    private let channelCount: UInt32 = 1
    private let logger = Logger(subsystem: "com.meetingrecorder", category: "AudioProcessor")

    private var transcriptionService: TranscriptionService?

    // Simplified mixing: We just append to a single buffer for now.
    // In a real app, we'd need a circular buffer and timestamp alignment.
    private var audioBuffer: [Float] = []
    private let bufferSizeThreshold = 16000 * 30  // Process every 30 seconds of audio

    func setTranscriptionService(_ service: TranscriptionService) {
        self.transcriptionService = service
    }

    func process(audioSamples: [Float], source: AudioSource) {
        // Simplified mixing: We just append to a single buffer for now.

        // Naive downsampling/mixing if needed.
        // For now, assuming input is already close to what we want or just taking it raw.

        audioBuffer.append(contentsOf: audioSamples)

        // Check if we have enough data to transcribe
        if audioBuffer.count >= bufferSizeThreshold {
            let chunkToProcess = Array(audioBuffer.prefix(bufferSizeThreshold))
            audioBuffer.removeFirst(bufferSizeThreshold)

            Task {
                do {
                    _ = try await transcriptionService?.transcribe(audioSamples: chunkToProcess)
                } catch {
                    logger.error("Transcription error: \(error.localizedDescription)")
                }
            }
        }
    }
}
