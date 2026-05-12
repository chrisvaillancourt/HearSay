import OSLog
import SwiftUI

struct RecordingView: View {
    @Binding var isRecording: Bool
    @ObservedObject var captureService: CaptureService
    @State private var isRestarting = false

    private let logger = Logger(subsystem: "MeetingRecorder", category: "RecordingView")

    var body: some View {
        VStack {
            // Show error banner with recovery options if in error state
            if case .error(let captureError) = captureService.captureState {
                errorBanner(for: captureError)
            } else if let error = captureService.error {
                // Fallback for legacy error string
                Text("Error: \(error)")
                    .foregroundStyle(.red)
                    .padding()
            }

            // Show appropriate content based on state
            switch captureService.captureState {
            case .idle:
                idleView
            case .starting:
                startingView
            case .recording:
                recordingView
            case .error:
                errorRecoveryView
            case .stopping:
                stoppingView
            }
        }
        .padding()
        .task {
            do {
                try await captureService.startCapture()
            } catch {
                logger.error("Failed to start capture: \(error)")
            }
        }
    }

    // MARK: - View Components

    private var idleView: some View {
        VStack(spacing: 16) {
            Text("Ready to Record")
                .font(.largeTitle)
            Text("Tap Start Recording to begin")
                .foregroundStyle(.secondary)
        }
    }

    private var startingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Starting capture...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingView: some View {
        VStack(spacing: 20) {
            HStack {
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
                Text("Recording in Progress")
                    .font(.largeTitle)
            }

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
    }

    private var stoppingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Stopping capture...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var errorRecoveryView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("Recording Stopped")
                .font(.title)
                .fontWeight(.semibold)

            if captureService.canRestart {
                Text("You can try to restart the recording")
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Button("Restart Recording") {
                        restartRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRestarting)

                    Button("Cancel") {
                        captureService.clearError()
                        isRecording = false
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("Please try again later")
                    .foregroundStyle(.secondary)

                Button("Close") {
                    captureService.clearError()
                    isRecording = false
                }
                .buttonStyle(.borderedProminent)
            }

            if isRestarting {
                ProgressView("Restarting...")
                    .padding(.top)
            }
        }
    }

    private func errorBanner(for error: CaptureError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.white)
                Text(error.localizedDescription ?? "An error occurred")
                    .foregroundStyle(.white)
                    .fontWeight(.medium)
                Spacer()
            }

            if error.isRecoverable {
                Text("This error may be temporary. You can try to restart.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.red.gradient)
        )
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func restartRecording() {
        isRestarting = true
        Task {
            do {
                try await captureService.restartCapture()
                await MainActor.run {
                    isRestarting = false
                }
            } catch {
                logger.error("Failed to restart capture: \(error)")
                await MainActor.run {
                    isRestarting = false
                }
            }
        }
    }
}
