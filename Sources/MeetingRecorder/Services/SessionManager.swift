import Foundation
import SwiftData
import OSLog

/// Manages meeting session lifecycle including creation, persistence, and file management
@MainActor
final class SessionManager: ObservableObject {
    private let logger = Logger(subsystem: "MeetingRecorder", category: "SessionManager")
    private let modelContext: ModelContext
    
    @Published var currentSession: MeetingSession?
    @Published var isRecording = false
    private var sessionStartTime: Date?
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Creates a new meeting session and starts recording
    func startSession(title: String = "Meeting \(DateFormatter.meetingDate.string(from: Date()))") throws {
        guard !isRecording else {
            logger.warning("Attempted to start session while already recording")
            throw SessionError.alreadyRecording
        }
        
        let session = MeetingSession(
            title: title,
            dateRecorded: Date()
        )
        
        modelContext.insert(session)
        currentSession = session
        sessionStartTime = Date()
        isRecording = true
        
        logger.info("Started new session: \(session.title)")
    }
    
    /// Adds transcript segments to the current session
    func addSegments(_ segments: [TranscriptSegment]) {
        guard let session = currentSession else {
            logger.warning("Cannot add segments: no active session")
            return
        }

        for segment in segments {
            segment.session = session
            session.segments.append(segment)
            modelContext.insert(segment)
        }

        logger.info("Added \(segments.count) segments to session: \(session.title)")
    }

    /// Ends the current session and saves it
    func endSession() throws {
        guard isRecording, let session = currentSession else {
            logger.warning("Attempted to end session while not recording")
            throw SessionError.notRecording
        }
        
        // Calculate duration
        if let startTime = sessionStartTime {
            session.duration = Date().timeIntervalSince(startTime)
        }
        
        // Generate media file path
        session.mediaFilePath = generateMediaFilePath(for: session)
        
        do {
            try modelContext.save()
            logger.info("Saved session: \(session.title) (\(session.duration)s)")
        } catch {
            logger.error("Failed to save session: \(error)")
            throw SessionError.saveFailed(error)
        }
        
        currentSession = nil
        isRecording = false
        sessionStartTime = nil
    }
    
    /// Deletes a session and its associated files
    func deleteSession(_ session: MeetingSession) throws {
        // Delete media file if it exists
        if !session.mediaFilePath.isEmpty {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let mediaFileURL = documentsPath.appendingPathComponent(session.mediaFilePath)
            
            if FileManager.default.fileExists(atPath: mediaFileURL.path) {
                try FileManager.default.removeItem(at: mediaFileURL)
                logger.info("Deleted media file: \(session.mediaFilePath)")
            }
        }
        
        // Delete from SwiftData
        modelContext.delete(session)
        try modelContext.save()
        
        logger.info("Deleted session: \(session.title)")
    }
    
    /// Fetches all sessions sorted by date (newest first)
    func fetchAllSessions() -> [MeetingSession] {
        let descriptor = FetchDescriptor<MeetingSession>(
            sortBy: [SortDescriptor(\.dateRecorded, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch sessions: \(error)")
            return []
        }
    }
    
    /// Generates a unique media file path for a session
    private func generateMediaFilePath(for session: MeetingSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: session.dateRecorded)
        
        // Sanitize title for filename
        let sanitizedTitle = session.title
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-zA-Z0-9_]", with: "", options: .regularExpression)
        
        return "Recordings/\(dateString)_\(sanitizedTitle).mp4"
    }
}

enum SessionError: LocalizedError {
    case alreadyRecording
    case notRecording
    case saveFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording session is already in progress"
        case .notRecording:
            return "No recording session is currently active"
        case .saveFailed(let error):
            return "Failed to save session: \(error.localizedDescription)"
        }
    }
}

extension DateFormatter {
    static let meetingDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}