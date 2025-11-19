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
    
    func setErrorHandler(_ handler: @escaping (any Error) -> Void) {
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
        // Detect input sample rate based on source
        let inputSampleRate = detectSampleRate(for: source)
        
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
        
        for i in 0..<outputLength {
            let sourceIndex = Double(i) / ratio
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
        
        let message = "Successfully resampled \(samples.count) samples from \(inputSampleRate)Hz to \(self.targetSampleRate)Hz using linear interpolation (\(resampledSamples.count) samples)"
        logger.info("\(message)")
        
        return resampledSamples
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
            let results = try await transcriptionService?.transcribe(audioSamples: chunk, source: source)
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
    case failedToCreateResampler
    case resamplingFailed
    
    var errorDescription: String? {
        switch self {
        case .failedToCreateFormat:
            return "Failed to create audio format"
        case .failedToCreateBuffer:
            return "Failed to create audio buffer"
        case .failedToCreateResampler:
            return "Failed to create audio resampler"
        case .resamplingFailed:
            return "Audio resampling failed"
        }
    }
}