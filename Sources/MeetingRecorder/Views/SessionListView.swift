import SwiftData
import SwiftUI

struct SessionListView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query(sort: \MeetingSession.dateRecorded, order: .reverse)
    private var sessions: [MeetingSession]
    @State private var selection: MeetingSession?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(sessions) { session in
                    NavigationLink(value: session) {
                        VStack(alignment: .leading) {
                            Text(session.title)
                                .font(.headline)
                            Text(session.dateRecorded, format: .dateTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("Meetings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let session = selection {
                VStack {
                    Text("Details for \(session.title)")
                    Text("Duration: \(Duration.seconds(session.duration).formatted())")

                    List(session.segments) { segment in
                        HStack {
                            Text(segment.speakerLabel)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text(segment.text)
                        }
                    }
                }
            } else {
                Text("Select a meeting")
            }
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = MeetingSession(title: "New Meeting", dateRecorded: Date())
            modelContext.insert(newItem)
            selection = newItem
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(sessions[index])
            }
        }
    }
}
