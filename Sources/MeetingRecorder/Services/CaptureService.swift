@preconcurrency import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import OSLog
@preconcurrency import ScreenCaptureKit
import SwiftData

/// CaptureService manages audio and video capture from microphone, webcam, and screen.
///
/// Concurrency Design:
/// - Uses `@unchecked Sendable` with proper synchronization via `InitializationStateManager`
/// - All mutable state accessed from nonisolated callbacks is protected by NSLock
/// - AVCaptureSession is managed on a dedicated `sessionQueue`
/// - Published properties are MainActor-isolated for UI binding
class CaptureService: NSObject, ObservableObject, @unchecked Sendable {
    let logger = Logger(subsystem: "com.meetingrecorder", category: "CaptureService")

    // AVFoundation (Mic + Webcam) - accessed on sessionQueue
    let avSession = AVCaptureSession()
    let sessionQueue = DispatchQueue(label: "com.meetingrecorder.sessionQueue")
    let audioQueue = DispatchQueue(label: "com.meetingrecorder.audio")
    let videoQueue = DispatchQueue(label: "com.meetingrecorder.video")

    // Audio Processing
    let audioProcessor = AudioProcessor()
    let transcriptionService = TranscriptionService()

    // Audio Mixing - combines system and microphone audio with proper synchronization
    let audioMixer = AudioMixer()

    // Timestamp tracking for accurate transcript-video correlation
    let sessionTimestamp = SessionTimestamp()

    // Session Management
    let sessionManager: SessionManager

    // Video Recording Pipeline
    let videoCompositor = VideoCompositor(pipScale: 0.2, pipPadding: 20, pipCornerRadius: 12)

    // State
    @MainActor @Published var captureState: CaptureState = .idle
    @MainActor @Published var isRecording = false
    @MainActor @Published var error: String?
    @MainActor @Published var lastError: CaptureError?
    @MainActor @Published var canRestart: Bool = false

    // Thread-safe state management for all mutable state accessed from nonisolated callbacks
    let stateManager = InitializationStateManager()

    // Convenience accessors for stateManager properties
    var stream: SCStream? {
        get { stateManager.stream }
        set { stateManager.stream = newValue }
    }

    var mediaWriter: MediaWriter? {
        get { stateManager.mediaWriter }
        set { stateManager.mediaWriter = newValue }
    }

    var useMixedAudio: Bool {
        get { stateManager.useMixedAudio }
        set { stateManager.useMixedAudio = newValue }
    }

    var captureWidth: Int {
        get { stateManager.captureWidth }
        set { stateManager.captureWidth = newValue }
    }

    var captureHeight: Int {
        get { stateManager.captureHeight }
        set { stateManager.captureHeight = newValue }
    }

    var isVideoRecordingEnabled: Bool {
        get { stateManager.isVideoRecordingEnabled }
        set { stateManager.isVideoRecordingEnabled = newValue }
    }

    @MainActor
    init(modelContext: ModelContext) {
        self.sessionManager = SessionManager(modelContext: modelContext)
        super.init()
        // AVSession setup is deferred to startCapture() to avoid redundant initialization
        setupAVSessionNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - AVSession Notifications

    /// Sets up observers for AVCaptureSession runtime errors and interruptions
    private func setupAVSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAVSessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification,
            object: avSession
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAVSessionInterrupted),
            name: AVCaptureSession.wasInterruptedNotification,
            object: avSession
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAVSessionInterruptionEnded),
            name: AVCaptureSession.interruptionEndedNotification,
            object: avSession
        )
    }

    @objc
    private func handleAVSessionRuntimeError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else {
            logger.error("AVCaptureSession runtime error with unknown error")
            return
        }

        logger.error("AVCaptureSession runtime error: \(error.localizedDescription)")
        let captureError = CaptureError.avSessionRuntimeError(error.localizedDescription)
        handleCaptureError(captureError)
    }

    @objc
    private func handleAVSessionInterrupted(_ notification: Notification) {
        logger.warning("AVCaptureSession interrupted")
        handleCaptureError(.avSessionInterrupted("Session was interrupted"))
    }

    @objc
    private func handleAVSessionInterruptionEnded(_ notification: Notification) {
        logger.info("AVCaptureSession interruption ended")

        Task { @MainActor in
            if case .error(let error) = self.captureState,
                case .avSessionInterrupted = error {
                self.logger.info("Attempting to resume after interruption")
                self.canRestart = true
            }
        }
    }

    // MARK: - Error Handling

    /// Centralized error handling - stops capture cleanly and updates state
    func handleCaptureError(_ error: CaptureError) {
        logger.error("Capture error occurred: \(error.localizedDescription ?? "Unknown error")")

        stopCaptureInternal(dueToError: true)

        Task { @MainActor in
            self.captureState = .error(error)
            self.lastError = error
            self.error = error.localizedDescription
            self.isRecording = false
            self.canRestart = error.isRecoverable
        }
    }

    // MARK: - Capture Lifecycle

    func startCapture() async throws {
        await MainActor.run {
            self.captureState = .starting
            self.error = nil
            self.lastError = nil
            self.canRestart = false
        }

        do {
            try await initializeServices()

            // Start timestamp tracking session before starting capture
            // so the first audio sample's timestamp becomes the reference point
            await sessionTimestamp.startSession()
            logger.info("Timestamp session started")

            try await startScreenCapture()

            if isVideoRecordingEnabled {
                try await startVideoRecording()
            }

            try await startAVSession()

            await MainActor.run {
                self.captureState = .recording
            }
        } catch {
            logger.error("Failed to start capture: \(error.localizedDescription)")
            await sessionTimestamp.endSession()
            let captureError = CaptureError.initializationFailed(error.localizedDescription)
            await MainActor.run {
                self.captureState = .error(captureError)
                self.error = captureError.localizedDescription
                self.lastError = captureError
                self.canRestart = captureError.isRecoverable
            }
            throw error
        }
    }

    /// Attempts to restart capture after an error
    func restartCapture() async throws {
        logger.info("Attempting to restart capture")

        await MainActor.run {
            self.captureState = .idle
            self.error = nil
            self.lastError = nil
            self.canRestart = false
        }

        stateManager.resetAVSessionConfigured()
        stream = nil

        await audioProcessor.reset()
        await audioMixer.reset()
        videoCompositor.shutdown()

        try await startCapture()
    }

    /// Public method to stop capture - used by UI
    func stopCapture() {
        stopCaptureInternal(dueToError: false)

        Task { @MainActor in
            self.captureState = .idle
            self.error = nil
            self.canRestart = false
        }
    }

    /// Internal method to stop capture - handles both user-initiated and error-driven stops
    private func stopCaptureInternal(dueToError: Bool) {
        logger.info("Stopping capture (dueToError: \(dueToError))")

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
            self.stream = nil
        }

        Task {
            await stopVideoRecording()
        }

        Task {
            await self.sessionTimestamp.endSession()
            self.logger.info("Timestamp session ended")
            await self.audioProcessor.reset()
            await self.audioMixer.reset()
        }

        Task { @MainActor in
            isRecording = false
        }
    }

    /// Clears the current error state - used after user acknowledges error
    @MainActor
    func clearError() {
        if case .error = captureState {
            captureState = .idle
        }
        error = nil
        lastError = nil
        canRestart = false
    }
}

// MARK: - Audio Mixing Configuration

extension CaptureService {
    /// Enables or disables audio mixing.
    /// When enabled, system and microphone audio are synchronized using CMClock alignment
    /// and mixed into a stereo stream (Left=System, Right=Microphone) for improved diarization.
    func setAudioMixingEnabled(_ enabled: Bool) {
        useMixedAudio = enabled
        logger.info("Audio mixing \(enabled ? "enabled" : "disabled")")
    }

    /// Returns whether audio mixing is currently enabled
    func isAudioMixingEnabled() -> Bool {
        useMixedAudio
    }

    /// Returns diagnostic information about the audio mixer state
    func getAudioMixerDiagnostics() async -> (bufferLevels: (system: Int, microphone: Int), isAligned: Bool) {
        let levels = await audioMixer.getBufferLevels()
        let aligned = await audioMixer.isClockAligned()
        return (levels, aligned)
    }
}
