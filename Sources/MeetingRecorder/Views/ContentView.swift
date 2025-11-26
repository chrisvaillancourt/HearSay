import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var captureService: CaptureService?
    @State private var isRecording = false

    var body: some View {
        Group {
            if isRecording {
                if let captureService = captureService {
                    RecordingView(isRecording: $isRecording, captureService: captureService)
                }
            } else {
                SessionListView()
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button(action: {
                                initializeCaptureService()
                                isRecording = true
                            }) {
                                Label("Start Recording", systemImage: "record.circle")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
            }
        }
        .onAppear {
            if captureService == nil {
                initializeCaptureService()
            }
        }
    }
    
    private func initializeCaptureService() {
        captureService = CaptureService(modelContext: modelContext)
    }
}
