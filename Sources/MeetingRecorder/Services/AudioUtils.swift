import AVFoundation
import CoreMedia
import OSLog

class AudioUtils {
    /// Extracts the sample rate from a CMSampleBuffer's audio format description.
    /// - Parameter sampleBuffer: The audio sample buffer to extract the sample rate from
    /// - Returns: The sample rate in Hz, or nil if it cannot be extracted
    static func extractSampleRate(from sampleBuffer: CMSampleBuffer) -> Double? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        else {
            return nil
        }
        return asbd.mSampleRate
    }

    static func convert(sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        else {
            return nil
        }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        if numSamples == 0 { return nil }

        // Create AVAudioFormat from ASBD
        var asbdCopy = asbd
        guard let format = AVAudioFormat(streamDescription: &asbdCopy) else { return nil }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        // Copy data
        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                let src = UnsafeMutableAudioBufferListPointer(audioBufferList.unsafeMutablePointer)
                let dst = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)

                for (idx, buffer) in src.enumerated() where idx < dst.count {
                    let dstBuffer = dst[idx]
                    if let srcData = buffer.mData, let dstData = dstBuffer.mData {
                        memcpy(dstData, srcData, Int(min(buffer.mDataByteSize, dstBuffer.mDataByteSize)))
                    }
                }
            }
        } catch {
            Logger(subsystem: "MeetingRecorder", category: "AudioUtils").error("Error converting buffer: \(error)")
            return nil
        }

        return pcmBuffer
    }
}
