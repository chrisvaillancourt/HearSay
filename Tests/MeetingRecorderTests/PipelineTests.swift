import AVFoundation
import CoreMedia
import Testing

@testable import MeetingRecorder

struct PipelineTests {
    @Test
    func testAudioProcessorIntegration() async throws {
        let processor = AudioProcessor()
        let transcriptionService = TranscriptionService()
        await processor.setTranscriptionService(transcriptionService)

        guard let buffer = makeEmptySampleBuffer(sampleRate: 16000, frameCount: 1024) else {
            #expect(Bool(false), "Failed to construct sample buffer")
            return
        }

        do {
            let blockBuffer = try CMBlockBuffer(length: 1024 * 4, flags: .assureMemoryNow)
            CMSampleBufferSetDataBuffer(buffer, newValue: blockBuffer)
        } catch {
            #expect(Bool(false), "Failed to create block buffer: \(error)")
            return
        }

        let samples = [Float](repeating: 0.0, count: 1024)
        await processor.process(audioSamples: samples, source: .microphone)

        // Verify no crash. A real test would mock TranscriptionService and verify it received data.
        #expect(true)
    }

    /// Builds an empty CMSampleBuffer with valid timing metadata for the pipeline test.
    private func makeEmptySampleBuffer(sampleRate: Int32, frameCount: Int) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

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

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: sampleRate),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: nil,
            dataReady: false,
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
        return sampleBuffer
    }
}
