import SwiftUI

struct RecordingView: View {
    @Binding var isRecording: Bool
    
    var body: some View {
        VStack {
            Text("Recording in Progress")
                .font(.largeTitle)
            
            // Placeholder for visualizer
            Rectangle()
                .fill(.gray.opacity(0.2))
                .frame(height: 200)
                .overlay(Text("Waveform Visualizer"))
                
            HStack {
                Button("Stop Recording") {
                    isRecording = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
            }
        }
        .padding()
    }
}
