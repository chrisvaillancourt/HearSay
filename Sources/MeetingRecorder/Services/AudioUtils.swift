import AVFoundation
import CoreMedia
import OSLog

class AudioUtils {
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

                for (i, buffer) in src.enumerated() {
                    if i < dst.count {
                        let dstBuffer = dst[i]
                        if let srcData = buffer.mData, let dstData = dstBuffer.mData {
                            memcpy(dstData, srcData, Int(min(buffer.mDataByteSize, dstBuffer.mDataByteSize)))
                        }
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
