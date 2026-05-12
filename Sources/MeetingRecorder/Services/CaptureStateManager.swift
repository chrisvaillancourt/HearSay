import Foundation
@preconcurrency import ScreenCaptureKit

/// Initialization state for thread-safe service initialization
enum InitializationState: Sendable, CustomStringConvertible {
    case uninitialized
    case initializing
    case initialized
    case failed(Error)

    var description: String {
        switch self {
        case .uninitialized: return "uninitialized"
        case .initializing: return "initializing"
        case .initialized: return "initialized"
        case .failed(let error): return "failed(\(error.localizedDescription))"
        }
    }
}

/// Thread-safe manager for initialization state and concurrent access protection.
/// Uses NSLock for thread-safe access to initialization state and task management.
/// Allows multiple concurrent callers to await the same initialization task.
final class InitializationStateManager: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: InitializationState = .uninitialized
    private var _initializationTask: Task<Void, Error>?
    private var _avSessionConfigured = false
    private var _useMixedAudio: Bool = true
    private var _stream: SCStream?
    private var _mediaWriter: MediaWriter?
    private var _captureWidth: Int = 1920
    private var _captureHeight: Int = 1080
    private var _isVideoRecordingEnabled = true

    var state: InitializationState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    var initializationTask: Task<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return _initializationTask
    }

    var isAVSessionConfigured: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _avSessionConfigured
    }

    var useMixedAudio: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _useMixedAudio
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _useMixedAudio = newValue
        }
    }

    var stream: SCStream? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _stream
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _stream = newValue
        }
    }

    var mediaWriter: MediaWriter? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _mediaWriter
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _mediaWriter = newValue
        }
    }

    var captureWidth: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _captureWidth
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _captureWidth = newValue
        }
    }

    var captureHeight: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _captureHeight
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _captureHeight = newValue
        }
    }

    var isVideoRecordingEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isVideoRecordingEnabled
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isVideoRecordingEnabled = newValue
        }
    }

    /// Attempts to transition to initializing state. Returns true if successful (was uninitialized).
    func tryBeginInitialization() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .uninitialized = _state else {
            return false
        }
        _state = .initializing
        return true
    }

    /// Marks initialization as complete.
    func markInitialized() {
        lock.lock()
        defer { lock.unlock() }
        guard case .initializing = _state else { return }
        _state = .initialized
    }

    /// Marks initialization as failed.
    func markFailed(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard case .initializing = _state else { return }
        _state = .failed(error)
    }

    /// Resets failed state back to uninitialized for retry.
    func resetFromFailed() {
        lock.lock()
        defer { lock.unlock() }
        guard case .failed = _state else { return }
        _state = .uninitialized
        _initializationTask = nil
    }

    /// Stores the initialization task.
    func setInitializationTask(_ task: Task<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        _initializationTask = task
    }

    /// Marks AVSession as configured.
    func markAVSessionConfigured() {
        lock.lock()
        defer { lock.unlock() }
        _avSessionConfigured = true
    }

    /// Resets AVSession configured flag for restart scenarios.
    func resetAVSessionConfigured() {
        lock.lock()
        defer { lock.unlock() }
        _avSessionConfigured = false
    }
}
