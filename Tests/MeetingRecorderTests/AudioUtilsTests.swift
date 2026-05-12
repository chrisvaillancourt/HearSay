import AVFoundation
import CoreMedia
import Testing

@testable import MeetingRecorder

struct AudioUtilsTests {
    @Test
    func testConvertCMSampleBufferToPCM() async throws {
        guard let buffer = try makeSilentSampleBuffer(sampleRate: 44100, frameCount: 1024) else {
            #expect(Bool(false), "Failed to construct sample buffer")
            return
        }

        let pcmBuffer = AudioUtils.convert(sampleBuffer: buffer)

        #expect(pcmBuffer != nil)
        #expect(pcmBuffer?.frameLength == 1024)
        #expect(pcmBuffer?.format.streamDescription.pointee.mSampleRate == 44100)
    }

    /// Builds a CMSampleBuffer of silence with the given sample rate and frame count.
    private func makeSilentSampleBuffer(sampleRate: Double, frameCount: Int) throws -> CMSampleBuffer? {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            return nil
        }

        var asbd = format.streamDescription.pointee
        var description: CMFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &description
        )
        guard let formatDescription = description else { return nil }

        let dataSize = frameCount * 4
        let blockBuffer = try CMBlockBuffer(length: dataSize, flags: .assureMemoryNow)

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(sampleRate)),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )

        let status = CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        return status == noErr ? sampleBuffer : nil
    }
}
