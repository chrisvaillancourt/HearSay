import SwiftUI

struct ContentView: View {
    @StateObject private var captureService = CaptureService()
    @State private var isRecording = false

    var body: some View {
        Group {
            if isRecording {
                RecordingView(isRecording: $isRecording, captureService: captureService)
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
