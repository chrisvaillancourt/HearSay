import Foundation
import SwiftData

@Model
final class MeetingSession {
    var id: UUID
    var title: String
    var dateRecorded: Date
    var duration: TimeInterval
    var mediaFilePath: String  // Relative URL

    @Relationship(deleteRule: .cascade)
    var segments: [TranscriptSegment] = []

    init(
        id: UUID = UUID(),
        title: String,
        dateRecorded: Date = Date(),
        duration: TimeInterval = 0,
        mediaFilePath: String = ""
    ) {
        self.id = id
        self.title = title
        self.dateRecorded = dateRecorded
        self.duration = duration
        self.mediaFilePath = mediaFilePath
    }
}

@Model
final class TranscriptSegment: @unchecked Sendable {
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var speakerLabel: String  // "Me", "System", or "Speaker 1"
    var session: MeetingSession?

    init(startTime: TimeInterval, endTime: TimeInterval, text: String, speakerLabel: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.speakerLabel = speakerLabel
    }
}
