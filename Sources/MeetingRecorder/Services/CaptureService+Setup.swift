@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

// MARK: - Initialization

extension CaptureService {
    /// Initializes all services required for capture. This method is idempotent and thread-safe.
    /// Multiple concurrent callers will all await the same initialization task.
    func initializeServices() async throws {
        switch stateManager.state {
        case .initialized:
            logger.debug("initializeServices called but already initialized")
            return

        case .failed(let previousError):
            stateManager.resetFromFailed()
            logger.info("Retrying initialization after previous failure: \(previousError.localizedDescription)")

        case .initializing:
            if let existingTask = stateManager.initializationTask {
                logger.info("Awaiting existing initialization task")
                try await existingTask.value
                return
            }
            throw CaptureError.initializationFailed("Initialization in progress but no task available")

        case .uninitialized:
            break
        }

        if stateManager.tryBeginInitialization() {
            logger.info("Starting CaptureService initialization")

            let task = Task { [weak self] in
                guard let self = self else {
                    throw CaptureError.selfDeallocated
                }
                try await self.performInitialization()
            }
            stateManager.setInitializationTask(task)

            do {
                try await task.value
                stateManager.markInitialized()
                logger.info("CaptureService initialization completed successfully")
            } catch {
                stateManager.markFailed(error)
                logger.error("CaptureService initialization failed: \(error.localizedDescription)")
                throw error
            }
        } else {
            if let existingTask = stateManager.initializationTask {
                logger.debug("Lost initialization race, awaiting winner's task")
                try await existingTask.value
            } else {
                try await initializeServices()
            }
        }
    }

    /// Performs the actual initialization work. Called only once by the winning initializer.
    private func performInitialization() async throws {
        try await setupAVSession()

        await audioProcessor.setTranscriptionService(transcriptionService)
        await audioProcessor.setSessionTimestamp(sessionTimestamp)
        try await transcriptionService.initialize()

        await audioProcessor.setErrorHandler { [weak self] error in
            Task { @MainActor [weak self] in
                self?.error = "Transcription failed: \(error.localizedDescription)"
            }
        }

        await audioProcessor.setSegmentHandler { [weak self] segments in
            Task { @MainActor [weak self] in
                self?.sessionManager.addSegments(segments)
            }
        }

        await audioMixer.setMixedOutputHandler { [weak self] leftChannel, rightChannel, timestamp in
            guard let self = self else { return }
            await self.audioProcessor.processMixedStereo(
                leftChannel: leftChannel,
                rightChannel: rightChannel,
                timestamp: timestamp
            )
        }
    }
}

// MARK: - AVSession Setup

extension CaptureService {
    func setupAVSession() async throws {
        guard !stateManager.isAVSessionConfigured else {
            logger.debug("AVSession already configured, skipping setup")
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CaptureError.selfDeallocated)
                    return
                }
                guard !self.stateManager.isAVSessionConfigured else {
                    self.logger.debug("AVSession already configured (checked on sessionQueue)")
                    continuation.resume()
                    return
                }

                self.avSession.beginConfiguration()
                do {
                    try self.attachMicrophoneInput()
                    self.attachWebcamInput()
                    self.avSession.commitConfiguration()
                    self.stateManager.markAVSessionConfigured()
                    self.logger.info("AVSession configured successfully")
                    continuation.resume()
                } catch {
                    self.avSession.commitConfiguration()
                    self.logger.error("Failed to create audio input: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Attaches the default microphone to the AVCaptureSession. Throws on failure.
    /// Caller must be on `sessionQueue` and have called `beginConfiguration`.
    fileprivate func attachMicrophoneInput() throws {
        guard let mic = AVCaptureDevice.default(for: .audio) else { return }

        let micInput = try AVCaptureDeviceInput(device: mic)
        guard avSession.canAddInput(micInput) else { return }
        avSession.addInput(micInput)

        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
        if avSession.canAddOutput(audioOutput) {
            avSession.addOutput(audioOutput)
        }
    }

    /// Attaches the default webcam to the AVCaptureSession. Logs errors but does not throw —
    /// audio capture is more important than video.
    /// Caller must be on `sessionQueue` and have called `beginConfiguration`.
    fileprivate func attachWebcamInput() {
        guard let camera = AVCaptureDevice.default(for: .video) else { return }

        do {
            let camInput = try AVCaptureDeviceInput(device: camera)
            guard avSession.canAddInput(camInput) else { return }
            avSession.addInput(camInput)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            if avSession.canAddOutput(videoOutput) {
                avSession.addOutput(videoOutput)
            }
        } catch {
            logger.error("Failed to create video input: \(error.localizedDescription)")
        }
    }

    func startAVSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CaptureError.selfDeallocated)
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
}

// MARK: - Screen Capture

extension CaptureService {
    func startScreenCapture() async throws {
        let content = try await SCShareableContent.current

        guard let display = content.displays.first else {
            throw CaptureError.noDisplayFound
        }

        let excludedApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])

        // Configure capture dimensions (2x for retina displays)
        captureWidth = display.width * 2
        captureHeight = display.height * 2

        let config = SCStreamConfiguration()
        config.width = captureWidth
        config.height = captureHeight
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)

        try await stream.startCapture()

        logger.info("Started screen capture: \(self.captureWidth)x\(self.captureHeight)")
    }
}

// MARK: - Video Recording

extension CaptureService {
    func startVideoRecording() async throws {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        let recordingsDir = documentsPath.appendingPathComponent("Recordings")

        if !FileManager.default.fileExists(atPath: recordingsDir.path) {
            try FileManager.default.createDirectory(
                at: recordingsDir,
                withIntermediateDirectories: true
            )
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: Date())
        let outputURL = recordingsDir.appendingPathComponent("\(dateString)_recording.mp4")

        mediaWriter = MediaWriter(
            outputURL: outputURL,
            videoWidth: captureWidth,
            videoHeight: captureHeight
        )

        do {
            try mediaWriter?.startWriting()
            logger.info("Started video recording to: \(outputURL.path)")
        } catch {
            logger.error("Failed to start video recording: \(error.localizedDescription)")
            throw CaptureError.videoRecordingFailed(error.localizedDescription)
        }
    }

    func stopVideoRecording() async {
        guard let writer = mediaWriter else { return }

        videoCompositor.shutdown()

        do {
            let outputURL = try await writer.finishWriting()
            logger.info("Video recording saved to: \(outputURL.path)")

            await MainActor.run {
                if let session = sessionManager.currentSession {
                    let documentsPath = FileManager.default.urls(
                        for: .documentDirectory,
                        in: .userDomainMask
                    )[0]
                    let relativePath = outputURL.path.replacingOccurrences(
                        of: documentsPath.path + "/",
                        with: ""
                    )
                    session.mediaFilePath = relativePath
                }
            }
        } catch {
            logger.error("Failed to finish video recording: \(error.localizedDescription)")
        }

        mediaWriter = nil
    }

    /// Sets whether video recording is enabled
    func setVideoRecordingEnabled(_ enabled: Bool) {
        isVideoRecordingEnabled = enabled
    }
}
