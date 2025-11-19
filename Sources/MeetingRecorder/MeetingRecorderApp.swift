import SwiftUI
import SwiftData

@main
struct MeetingRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [MeetingSession.self, TranscriptSegment.self])
    }
}
