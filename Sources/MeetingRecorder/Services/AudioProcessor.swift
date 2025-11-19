import AVFoundation
import CoreMedia
import OSLog

enum AudioSource {
    case microphone
    case system
}

actor AudioProcessor {
    // Configuration
    private let targetSampleRate: Double = 16000.0  // WhisperKit expects 16kHz
    private let channelCount: UInt32 = 1
    private let logger = Logger(subsystem: "com.meetingrecorder", category: "AudioProcessor")
    
    // Buffer management
    private var audioBuffer: [Float] = []
    private let bufferSizeThreshold = 16000 * 30  // Process every 30 seconds of audio
    private let maxBufferSize = 16000 * 60 * 5  // Maximum 5 minutes to prevent unbounded growth
    
    // Audio resamplers for different input sample rates
    private var microphoneResampler: AVAudioConverter?
    private var systemResampler: AVAudioConverter?
    
    // Error handling
    private var errorHandler: ((Error) -> Void)?
    
    private var transcriptionService: TranscriptionService?

    func setTranscriptionService(_ service: TranscriptionService) {
        self.transcriptionService = service
    }
    
    func setErrorHandler(_ handler: @escaping (Error) -> Void) {
        self.errorHandler = handler
    }
    
    func reset() {
        audioBuffer.removeAll()
        logger.info("AudioProcessor buffer reset")
    }

    func process(audioSamples: [Float], source: AudioSource) async {
        do {
            // Resample audio to 16kHz if needed
            let resampledSamples = try await resampleAudio(audioSamples, source: source)
            
            // Add to buffer with size limit check
            audioBuffer.append(contentsOf: resampledSamples)
            
            // Prevent unbounded growth
            if audioBuffer.count > maxBufferSize {
                let excessCount = audioBuffer.count - maxBufferSize
                audioBuffer.removeFirst(excessCount)
                logger.warning("Audio buffer exceeded maximum size, dropped \(excessCount) samples")
            }
            
            // Check if we have enough data to transcribe
            while audioBuffer.count >= bufferSizeThreshold {
                let chunkToProcess = Array(audioBuffer.prefix(bufferSizeThreshold))
                audioBuffer.removeFirst(bufferSizeThreshold)
                
                await transcribeChunk(chunkToProcess, source: source)
            }
        } catch {
            logger.error("Audio processing error: \(error.localizedDescription)")
            errorHandler?(error)
        }
    }
    
    private func resampleAudio(_ samples: [Float], source: AudioSource) async throws -> [Float] {
        // TODO: Implement proper sample rate detection and resampling
        // For now, assume input is already at 16kHz or close enough
        // This is a placeholder that should be enhanced with AVAudioConverter
        
        // Log the source for debugging
        logger.info("Processing audio from \(String(describing: source)) source")
        
        // For now, return samples as-is (assuming they're already 16kHz)
        // In a production implementation, we would:
        // 1. Detect input sample rate from CMSampleBuffer
        // 2. Create AVAudioConverter from input rate to 16kHz
        // 3. Convert and return resampled samples
        
        return samples
    }
    
    private func detectSampleRate(for source: AudioSource) -> Double {
        // Detect typical sample rates based on audio source
        switch source {
        case .microphone:
            // Microphone typically captures at 44.1kHz or 48kHz
            // For now, assume 44.1kHz (most common for built-in mics)
            return 44100.0
        case .system:
            // ScreenCaptureKit typically captures at 48kHz
            return 48000.0
        }
    }
    
    private func getResampler(for source: AudioSource, inputRate: Double) -> AVAudioConverter? {
        // Get or create appropriate resampler for this source
        switch source {
        case .microphone:
            if microphoneResampler == nil {
                // Create microphone resampler
                guard let inputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: inputRate,
                    channels: 1,
                    interleaved: false
                ) else {
                    return nil
                }
                
                guard let outputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: targetSampleRate,
                    channels: 1,
                    interleaved: false
                ) else {
                    return nil
                }
                
                microphoneResampler = AVAudioConverter(from: inputFormat, to: outputFormat)
            }
            return microphoneResampler
            
        case .system:
            if systemResampler == nil {
                // Create system resampler
                guard let inputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: inputRate,
                    channels: 1,
                    interleaved: false
                ) else {
                    return nil
                }
                
                guard let outputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: targetSampleRate,
                    channels: 1,
                    interleaved: false
                ) else {
                    return nil
                }
                
                systemResampler = AVAudioConverter(from: inputFormat, to: outputFormat)
            }
            return systemResampler
        }
    }
    
    private func transcribeChunk(_ chunk: [Float], source: AudioSource) async {
        do {
            let results = try await transcriptionService?.transcribe(audioSamples: chunk)
            logger.info("Transcription completed for \(String(describing: source)) audio: \(results?.count ?? 0) segments")
        } catch {
            logger.error("Transcription error for \(String(describing: source)) audio: \(error.localizedDescription)")
            errorHandler?(error)
        }
    }
    
    // MARK: - Buffer Management
    
    func getBufferSize() -> Int {
        return audioBuffer.count
    }
}

enum AudioProcessorError: Error, LocalizedError {
    case failedToCreateFormat
    case failedToCreateBuffer
    case resamplingFailed
    
    var errorDescription: String? {
        switch self {
        case .failedToCreateFormat:
            return "Failed to create audio format"
        case .failedToCreateBuffer:
            return "Failed to create audio buffer"
        case .resamplingFailed:
            return "Audio resampling failed"
        }
    }
}