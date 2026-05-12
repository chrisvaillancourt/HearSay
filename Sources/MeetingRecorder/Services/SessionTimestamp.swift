import CoreMedia
import Foundation
import OSLog

/// Manages timestamp tracking for a recording session to enable correlation
/// between transcript segments and the media timeline.
///
/// This service converts between CMTime (used by AVFoundation/CoreMedia),
/// TimeInterval (used by TranscriptSegment), and maintains a consistent
/// timeline reference for the entire recording session.
actor SessionTimestamp {
    private let logger = Logger(subsystem: "MeetingRecorder", category: "SessionTimestamp")

    /// The first presentation timestamp received in this session (used as reference point)
    private var sessionStartTime: CMTime?

    /// Whether the session has been started
    private var isSessionActive = false

    // MARK: - Session Lifecycle

    /// Starts a new timestamp tracking session.
    /// Call this when recording begins, before processing any audio.
    func startSession() {
        sessionStartTime = nil
        isSessionActive = true
        logger.info("Timestamp session started")
    }

    /// Ends the current timestamp tracking session.
    func endSession() {
        isSessionActive = false
        sessionStartTime = nil
        logger.info("Timestamp session ended")
    }

    // MARK: - Timestamp Recording

    /// Records the presentation timestamp of incoming media.
    /// The first timestamp received becomes the session reference point.
    ///
    /// - Parameter presentationTime: The CMTime from CMSampleBufferGetPresentationTimeStamp
    /// - Returns: The elapsed time since session start in seconds, or nil if session not active
    func recordTimestamp(_ presentationTime: CMTime) -> TimeInterval? {
        guard isSessionActive else {
            logger.warning("Attempted to record timestamp without active session")
            return nil
        }

        guard presentationTime.isValid else {
            logger.warning("Invalid presentation timestamp received")
            return nil
        }

        // Set reference point on first valid timestamp
        if sessionStartTime == nil {
            sessionStartTime = presentationTime
            logger.info("Session start time set: \(presentationTime.seconds)s")
            return 0.0
        }

        guard let startTime = sessionStartTime else {
            return nil
        }

        // Calculate elapsed time using CMTime arithmetic for precision
        let elapsed = CMTimeSubtract(presentationTime, startTime)
        return CMTimeGetSeconds(elapsed)
    }

    // MARK: - Time Conversion

    /// Converts a CMTime to session-relative TimeInterval.
    ///
    /// - Parameter time: The CMTime to convert
    /// - Returns: TimeInterval relative to session start, or nil if session not started
    func toSessionTime(_ time: CMTime) -> TimeInterval? {
        guard let startTime = sessionStartTime, time.isValid else {
            return nil
        }

        let elapsed = CMTimeSubtract(time, startTime)
        return CMTimeGetSeconds(elapsed)
    }

    /// Converts a session-relative TimeInterval back to CMTime.
    ///
    /// - Parameter timeInterval: The session-relative time in seconds
    /// - Returns: CMTime for the given session time, or invalid CMTime if session not started
    func toCMTime(_ timeInterval: TimeInterval) -> CMTime {
        guard let startTime = sessionStartTime else {
            return CMTime.invalid
        }

        // Use high precision timescale (nanoseconds)
        let offsetTime = CMTime(seconds: timeInterval, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        return CMTimeAdd(startTime, offsetTime)
    }

    /// Returns the current session duration based on wall clock time.
    /// Useful for UI display when no recent media timestamp is available.
    ///
    /// - Returns: The elapsed session time, or 0 if session not started
    func getCurrentDuration() -> TimeInterval {
        guard sessionStartTime != nil else {
            return 0
        }
        // For wall clock estimation, we don't have a "current" media time,
        // so this is mainly for the session being active
        return 0
    }

    /// Returns whether a timestamp session is currently active
    func isActive() -> Bool {
        isSessionActive
    }

    /// Returns the session start CMTime for reference
    func getSessionStartTime() -> CMTime? {
        sessionStartTime
    }
}

// MARK: - CMTime Extensions for Convenience

extension CMTime {
    /// Returns whether this CMTime represents a valid timestamp
    var isValid: Bool {
        CMTIME_IS_VALID(self)
    }

    /// Returns whether this CMTime is numeric (not indefinite or invalid)
    var isNumeric: Bool {
        CMTIME_IS_NUMERIC(self)
    }
}
