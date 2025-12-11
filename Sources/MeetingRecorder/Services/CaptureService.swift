@preconcurrency import AVFoundation
import CoreImage
import Foundation
import OSLog
@preconcurrency import ScreenCaptureKit
import SwiftData

class CaptureService: NSObject, ObservableObject, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.meetingrecorder", category: "CaptureService")

    // AVFoundation (Mic + Webcam)
    // Accessed on sessionQueue
    private let avSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.meetingrecorder.sessionQueue")
    private let initializationQueue = DispatchQueue(label: "com.meetingrecorder.initializationQueue")

    private let audioQueue = DispatchQueue(label: "com.meetingrecorder.audio")
    private let videoQueue = DispatchQueue(label: "com.meetingrecorder.video")

    // ScreenCaptureKit
    private var stream: SCStream?

    // Audio Processing
    let audioProcessor = AudioProcessor()
    let transcriptionService = TranscriptionService()
    
    // Session Management
    private let sessionManager: SessionManager
    private var mediaWriter: MediaWriter?

    // State
    @MainActor @Published var isRecording = false
    @MainActor @Published var error: String?

    private var isInitialized = false

    @MainActor
    init(modelContext: ModelContext) {
        self.sessionManager = SessionManager(modelContext: modelContext)
        super.init()
        // Initialize services synchronously
        Task {
            try await setupAVSession()
        }
    }

    func initializeServices() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            initializationQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(
                      throwing: NSError(
                        domain: "CaptureService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Self is nil"]
                      )
                    )
                    return
                }

                guard !self.isInitialized else {
                    continuation.resume()
                    return
                }

                Task {
                    do {
                        await self.audioProcessor.setTranscriptionService(self.transcriptionService)
                        try await self.transcriptionService.initialize()

                        // Set up error handling once
                        await self.audioProcessor.setErrorHandler { [weak self] error in
                            Task { @MainActor [weak self] in
                                self?.error = "Transcription failed: \(error.localizedDescription)"
                            }
                        }

                        // Set up segment persistence handler
                        await self.audioProcessor.setSegmentHandler { [weak self] segments in
                            Task { @MainActor [weak self] in
                                self?.sessionManager.addSegments(segments)
                            }
                        }

                        self.isInitialized = true
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func setupAVSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(
                      throwing: NSError(
                        domain: "CaptureService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Self is nil"]
                      )
                    )
                    return
                }

                self.avSession.beginConfiguration()

                // 1. Microphone
                if let mic = AVCaptureDevice.default(for: .audio) {
                    do {
                        let micInput = try AVCaptureDeviceInput(device: mic)
                        if self.avSession.canAddInput(micInput) {
                            self.avSession.addInput(micInput)

                            let audioOutput = AVCaptureAudioDataOutput()
                            audioOutput.setSampleBufferDelegate(self, queue: self.audioQueue)
                            if self.avSession.canAddOutput(audioOutput) {
                                self.avSession.addOutput(audioOutput)
                            }
                        }
                    } catch {
                        self.logger.error("Failed to create audio input: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }
                }

                // 2. Webcam
                if let camera = AVCaptureDevice.default(for: .video) {
                    do {
                        let camInput = try AVCaptureDeviceInput(device: camera)
                        if self.avSession.canAddInput(camInput) {
                            self.avSession.addInput(camInput)

                            let videoOutput = AVCaptureVideoDataOutput()
                            videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                            if self.avSession.canAddOutput(videoOutput) {
                                self.avSession.addOutput(videoOutput)
                            }
                        }
                    } catch {
                        self.logger.error("Failed to create video input: \(error.localizedDescription)")
                        // Don't fail for video errors, audio is more important
                    }
                }

                self.avSession.commitConfiguration()
                continuation.resume()
            }
        }
    }

    private func startAVSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(
                      throwing: NSError(
                        domain: "CaptureService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Self is nil"]
                      )
                    )
                    return
                }

                if !self.avSession.isRunning {
                    self.avSession.startRunning()
                    Task { @MainActor in
                        self.isRecording = true
                    }
                }
                continuation.resume()
            }
        }
    }

    func startCapture() async throws {
        // Ensure services are initialized first
        try await initializeServices()

        // Wait for AVSession setup to complete
        try await setupAVSession()

        // Start SCStream
        do {
            try await startScreenCapture()
        } catch {
            logger.error("Failed to start screen capture: \(error.localizedDescription)")
            await MainActor.run {
                self.error = "Screen capture failed: \(error.localizedDescription)"
            }
            throw error
        }

        // Start AVSession
        try await startAVSession()
    }

    func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.avSession.isRunning {
                self.avSession.stopRunning()
            }
        }

        if let stream = stream {
            let currentStream = stream
            Task {
                try? await currentStream.stopCapture()
            }
        }

        // Clear audio buffer when stopping
        Task {
            await audioProcessor.reset()
        }

        Task { @MainActor in
            isRecording = false
        }
    }

    private func startScreenCapture() async throws {
        let content = try await SCShareableContent.current

        guard let display = content.displays.first else {
            throw NSError(domain: "CaptureService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }

        let excludedApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = display.width * 2
        config.height = display.height * 2
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.showsCursor = true

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        self.stream = stream

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)

        try await stream.startCapture()
    }
}

extension CaptureService: AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate,
    SCStreamOutput {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        if output is AVCaptureAudioDataOutput {
            guard let pcmBuffer = AudioUtils.convert(sampleBuffer: sampleBuffer),
                let floatChannelData = pcmBuffer.floatChannelData
            else { return }

            let frameLength = Int(pcmBuffer.frameLength)
            let channelData = floatChannelData[0]

            // Create a copy of the data to pass to the actor
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

            Task {
                await self.audioProcessor.process(audioSamples: samples, source: .microphone)
            }
        } else {
            // Handle Webcam Video
        }
    }

    nonisolated func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
    ) {
        switch type {
        case .screen:
            break
        case .audio:
            guard let pcmBuffer = AudioUtils.convert(sampleBuffer: sampleBuffer),
                let floatChannelData = pcmBuffer.floatChannelData
            else { return }

            let frameLength = Int(pcmBuffer.frameLength)
            let channelData = floatChannelData[0]

            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

            Task {
                await self.audioProcessor.process(audioSamples: samples, source: .system)
            }
        case .microphone:
            break
        @unknown default:
            break
        }
    }
}
