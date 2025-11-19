import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreGraphics
import AppKit

@MainActor
class PermissionsService: ObservableObject {
    @Published var hasMicrophoneAccess: Bool = false
    @Published var hasScreenRecordingAccess: Bool = false
    @Published var hasCameraAccess: Bool = false
    
    init() {
        checkPermissions()
    }
    
    func checkPermissions() {
        checkMicrophoneAccess()
        checkCameraAccess()
        checkScreenRecordingAccess()
    }
    
    func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                self.hasMicrophoneAccess = granted
            }
        }
    }
    
    func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                self.hasCameraAccess = granted
            }
        }
    }
    
    private func checkMicrophoneAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasMicrophoneAccess = true
        default:
            hasMicrophoneAccess = false
        }
    }
    
    private func checkCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasCameraAccess = true
        default:
            hasCameraAccess = false
        }
    }
    
    private func checkScreenRecordingAccess() {
        // Modern check for macOS 15+
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                await MainActor.run {
                    self.hasScreenRecordingAccess = true
                }
            } catch {
                await MainActor.run {
                    self.hasScreenRecordingAccess = false
                }
            }
        }
    }
    
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording") {
            NSWorkspace.shared.open(url)
        }
    }
}
