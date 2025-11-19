import AVFoundation
import CoreMedia

enum AudioSource {
    case microphone
    case system
}

actor AudioProcessor {
    // Configuration
    private let sampleRate: Double = 16000.0 // Whisper usually likes 16kHz
    private let channelCount: UInt32 = 1 // Processing mono for transcription mostly, but spec says Stereo for diarization.
    // Let's target Stereo 16kHz: Left=System, Right=Mic
    
    private var audioBuffer = [Float]()
    
    func process(sampleBuffer: CMSampleBuffer, source: AudioSource) {
        guard let _ = AudioUtils.convert(sampleBuffer: sampleBuffer) else { return }
        
        // Here we would implement the complex mixing logic:
        // 1. Resample to target rate (16kHz) if necessary.
        // 2. Sync based on timestamps.
        // 3. Map to channels.
        
        // For prototype: Just log/drop
        // print("Received \(pcmBuffer.frameLength) frames from \(source)")
    }
}
