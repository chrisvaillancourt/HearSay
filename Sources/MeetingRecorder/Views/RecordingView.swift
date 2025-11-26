import SwiftUI
import OSLog

struct RecordingView: View {
    @Binding var isRecording: Bool
    @ObservedObject var captureService: CaptureService

    var body: some View {
        VStack {
            if let error = captureService.error {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
                    .padding()
            }

            Text("Recording in Progress")
                .font(.largeTitle)

            // Placeholder for visualizer
            Rectangle()
                .fill(.gray.opacity(0.2))
                .frame(height: 200)
                .overlay(Text("Waveform Visualizer"))

            HStack {
                Button("Stop Recording") {
                    captureService.stopCapture()
                    isRecording = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
            }
        }
        .padding()
        .task {
            do {
                try await captureService.startCapture()
            } catch {
                Logger(subsystem: "MeetingRecorder", category: "Capture").error("Failed to start capture: \(error)")
            }
        }
    }
}
