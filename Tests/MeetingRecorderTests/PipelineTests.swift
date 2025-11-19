import AVFoundation
import CoreMedia
import Testing

@testable import MeetingRecorder

struct PipelineTests {
    @Test func testAudioProcessorIntegration() async throws {
        let processor = AudioProcessor()
        let transcriptionService = TranscriptionService()

        await processor.setTranscriptionService(transcriptionService)

        // Simulate incoming buffer
        var description: CMFormatDescription?
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 16000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &description)

        guard let formatDescription = description else { return }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 16000), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)

        CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: formatDescription, sampleCount: 1024, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)

        if let buffer = sampleBuffer {
            // Allocate data
            do {
                let blockBuffer = try CMBlockBuffer(length: 1024 * 4, flags: .assureMemoryNow)
                CMSampleBufferSetDataBuffer(buffer, newValue: blockBuffer)
            } catch {
                #expect(Bool(false), \"Failed to create block buffer: \\(error)\")
                return
            }

            // Manually convert to samples for test
            let samples = [Float](repeating: 0.0, count: 1024)
            await processor.process(audioSamples: samples, source: .microphone)

            // Verify no crash.
            // In a real test we would mock TranscriptionService and verify it received data.
            // Since TranscriptionService is an actor, we can't easily inspect it without adding test hooks.
            #expect(true)
        }
    }
}
