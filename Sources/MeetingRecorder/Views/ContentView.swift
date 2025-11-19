import SwiftUI

struct ContentView: View {
    @State private var isRecording = false
    
    var body: some View {
        Group {
            if isRecording {
                RecordingView(isRecording: $isRecording)
            } else {
                SessionListView()
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button(action: {
                                isRecording = true
                            }) {
                                Label("Start Recording", systemImage: "record.circle")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
            }
        }
    }
}
