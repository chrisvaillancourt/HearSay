import Testing
import AVFoundation
import CoreMedia
@testable import MeetingRecorder

struct AudioUtilsTests {
    @Test func testConvertCMSampleBufferToPCM() async throws {
        // Create a dummy CMSampleBuffer using AVAudioFormat to ensure valid ASBD
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) else {
            #expect(Bool(false), "Failed to create AVAudioFormat")
            return
        }
        
        var asbd = format.streamDescription.pointee
        var description: CMFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        
        guard let formatDescription = description else {
            #expect(Bool(false), "Failed to create format description")
            return
        }
        
        // Allocate data for the buffer
        let dataSize = 1024 * 4
        let blockBuffer = try! CMBlockBuffer(length: dataSize, flags: .assureMemoryNow)
        
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44100), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        
        let status = CMSampleBufferCreate(allocator: nil, dataBuffer: blockBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription, sampleCount: 1024, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
        
        guard status == noErr, let buffer = sampleBuffer else {
            #expect(Bool(false), "Failed to create sample buffer: \(status)")
            return
        }
        
        // Test conversion
        let pcmBuffer = AudioUtils.convert(sampleBuffer: buffer)
        
        #expect(pcmBuffer != nil)
        #expect(pcmBuffer?.frameLength == 1024)
        #expect(pcmBuffer?.format.streamDescription.pointee.mSampleRate == 44100)
    }
}
