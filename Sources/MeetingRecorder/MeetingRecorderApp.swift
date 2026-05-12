import SwiftData
import SwiftUI

@main
struct MeetingRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [MeetingSession.self, TranscriptSegment.self])
    }
}
