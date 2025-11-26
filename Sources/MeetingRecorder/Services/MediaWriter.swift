import Foundation
import AVFoundation
import CoreMedia
import OSLog

/// Handles writing audio and video data to files using AVAssetWriter
@MainActor
final class MediaWriter: NSObject {
    private let logger = Logger(subsystem: "MeetingRecorder", category: "MediaWriter")
    
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var videoInput: AVAssetWriterInput?
    private var audioAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private let outputURL: URL
    private var isRecording = false
    
    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
    }
    
    /// Starts the media writer with audio and video inputs
    func startWriting() throws {
        guard !isRecording else {
            logger.warning("Already recording")
            throw MediaWriterError.alreadyRecording
        }
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        // Setup audio input
        setupAudioInput()
        
        // Setup video input  
        setupVideoInput()
        
        // Start writing
        guard let assetWriter = assetWriter else {
            throw MediaWriterError.setupFailed("Asset writer not initialized")
        }
        
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        
        isRecording = true
        logger.info("Started media writing to: \(self.outputURL.path)")
    }
    
    /// Appends audio sample buffer to the recording
    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let audioInput = audioInput,
              audioInput.isReadyForMoreMediaData else {
            return
        }
        
        audioInput.append(sampleBuffer)
    }
    
    /// Appends video sample buffer to the recording
    func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let videoInput = videoInput,
              videoInput.isReadyForMoreMediaData else {
            return
        }
        
        videoInput.append(sampleBuffer)
    }
    
    /// Finishes writing and saves the file
    func finishWriting() async throws -> URL {
        guard isRecording else {
            throw MediaWriterError.notRecording
        }
        
        guard let assetWriter = assetWriter else {
            throw MediaWriterError.setupFailed("Asset writer not initialized")
        }
        
        // Mark inputs as finished
        audioInput?.markAsFinished()
        videoInput?.markAsFinished()
        
        isRecording = false
        
        // Wait for writing to complete
        return try await withCheckedThrowingContinuation { continuation in
            assetWriter.finishWriting { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else {
                        continuation.resume(throwing: MediaWriterError.setupFailed("Self is nil"))
                        return
                    }
                    
                    let status = assetWriter.status
                    switch status {
                    case .completed:
                        self.logger.info("Finished writing media file: \(self.outputURL.path)")
                        continuation.resume(returning: self.outputURL)
                    case .failed:
                        let error = assetWriter.error ?? MediaWriterError.writingFailed("Unknown error")
                        self.logger.error("Failed to write media file: \(error)")
                        continuation.resume(throwing: error)
                    case .cancelled:
                        continuation.resume(throwing: MediaWriterError.writingCancelled)
                    default:
                        continuation.resume(throwing: MediaWriterError.writingFailed("Unexpected status: \(status.rawValue)"))
                    }
                }
            }
        }
    }
    
    /// Cancels the current writing session
    func cancelWriting() {
        guard isRecording else { return }
        
        assetWriter?.cancelWriting()
        isRecording = false
        
        logger.info("Cancelled media writing")
    }
    
    // MARK: - Private Setup Methods
    
    private func setupAudioInput() {
        guard let assetWriter = assetWriter else { return }
        
        // Audio settings for AAC
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        
        if let audioInput = audioInput {
            assetWriter.add(audioInput)
        }
    }
    
    private func setupVideoInput() {
        guard let assetWriter = assetWriter else { return }
        
        // Video settings for H.264
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5000000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        videoInput?.transform = CGAffineTransform(rotationAngle: .pi / 2) // Rotate for portrait
        
        if let videoInput = videoInput {
            assetWriter.add(videoInput)
        }
    }
}

enum MediaWriterError: LocalizedError {
    case alreadyRecording
    case notRecording
    case setupFailed(String)
    case writingFailed(String)
    case writingCancelled
    
    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Media writer is already recording"
        case .notRecording:
            return "Media writer is not currently recording"
        case .setupFailed(let reason):
            return "Failed to setup media writer: \(reason)"
        case .writingFailed(let reason):
            return "Failed to write media: \(reason)"
        case .writingCancelled:
            return "Media writing was cancelled"
        }
    }
}