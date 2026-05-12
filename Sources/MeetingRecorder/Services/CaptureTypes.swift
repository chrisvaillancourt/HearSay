import Foundation

/// Represents the current state of the capture pipeline
enum CaptureState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case error(CaptureError)
    case stopping

    var isActive: Bool {
        switch self {
        case .recording, .starting:
            return true
        default:
            return false
        }
    }
}

/// Errors that can occur during capture
enum CaptureError: Error, LocalizedError, Equatable, Sendable {
    case avSessionRuntimeError(String)
    case avSessionInterrupted(String)
    case screenCaptureError(String)
    case screenCaptureStopped(String)
    case initializationFailed(String)
    case noDisplayFound
    case selfDeallocated
    case videoRecordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .avSessionRuntimeError(let message):
            return "Camera/microphone error: \(message)"
        case .avSessionInterrupted(let reason):
            return "Recording interrupted: \(reason)"
        case .screenCaptureError(let message):
            return "Screen capture error: \(message)"
        case .screenCaptureStopped(let message):
            return "Screen capture stopped: \(message)"
        case .initializationFailed(let message):
            return "Failed to initialize: \(message)"
        case .noDisplayFound:
            return "No display found for screen capture"
        case .selfDeallocated:
            return "Capture service was deallocated"
        case .videoRecordingFailed(let message):
            return "Video recording failed: \(message)"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .avSessionInterrupted:
            return true
        case .avSessionRuntimeError, .screenCaptureError, .screenCaptureStopped, .videoRecordingFailed:
            return true
        case .initializationFailed, .noDisplayFound, .selfDeallocated:
            return false
        }
    }
}
