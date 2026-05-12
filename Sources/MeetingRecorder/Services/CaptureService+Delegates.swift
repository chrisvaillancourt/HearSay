@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

// MARK: - SCStreamDelegate

extension CaptureService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let errorMessage = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.logger.error("SCStream stopped with error: \(errorMessage)")
            let captureError = CaptureError.screenCaptureStopped(errorMessage)
            self.handleCaptureError(captureError)
        }
    }
}

// MARK: - AVCapture and SCStream Output Delegates

extension CaptureService: AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate,
    SCStreamOutput {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        if output is AVCaptureAudioDataOutput {
            let actualSampleRate = AudioUtils.extractSampleRate(from: sampleBuffer)
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            guard let pcmBuffer = AudioUtils.convert(sampleBuffer: sampleBuffer),
                let floatChannelData = pcmBuffer.floatChannelData
            else { return }

            let frameLength = Int(pcmBuffer.frameLength)
            let channelData = floatChannelData[0]
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

            Task {
                if self.useMixedAudio {
                    let buffer = TimestampedAudioBuffer(
                        samples: samples,
                        timestamp: presentationTime,
                        source: .microphone,
                        sampleRate: actualSampleRate ?? 44100.0
                    )
                    await self.audioMixer.receive(buffer: buffer)
                } else {
                    await self.audioProcessor.process(
                        audioSamples: samples,
                        source: .microphone,
                        sampleRate: actualSampleRate,
                        presentationTime: presentationTime
                    )
                }
            }

            mediaWriter?.appendAudioSample(sampleBuffer)
        } else if output is AVCaptureVideoDataOutput {
            self.videoCompositor.updateWebcamFrame(sampleBuffer)
        }
    }

    nonisolated func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
    ) {
        switch type {
        case .screen:
            processScreenFrame(sampleBuffer)

        case .audio:
            let actualSampleRate = AudioUtils.extractSampleRate(from: sampleBuffer)
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            guard let pcmBuffer = AudioUtils.convert(sampleBuffer: sampleBuffer),
                let floatChannelData = pcmBuffer.floatChannelData
            else { return }

            let frameLength = Int(pcmBuffer.frameLength)
            let channelData = floatChannelData[0]
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

            Task {
                if self.useMixedAudio {
                    let buffer = TimestampedAudioBuffer(
                        samples: samples,
                        timestamp: presentationTime,
                        source: .system,
                        sampleRate: actualSampleRate ?? 48000.0
                    )
                    await self.audioMixer.receive(buffer: buffer)
                } else {
                    await self.audioProcessor.process(
                        audioSamples: samples,
                        source: .system,
                        sampleRate: actualSampleRate,
                        presentationTime: presentationTime
                    )
                }
            }

            mediaWriter?.appendAudioSample(sampleBuffer)

        case .microphone:
            break

        @unknown default:
            break
        }
    }

    /// Processes screen frames - composites with webcam and writes to media file
    private nonisolated func processScreenFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let writer = mediaWriter else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if let compositedBuffer = self.videoCompositor.composite(screenBuffer: sampleBuffer) {
            writer.appendVideoPixelBuffer(compositedBuffer, presentationTime: presentationTime)
        } else if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            writer.appendVideoPixelBuffer(pixelBuffer, presentationTime: presentationTime)
        }
    }
}
