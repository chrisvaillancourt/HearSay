import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import OSLog
import VideoToolbox

/// Handles writing audio and video data to files using AVAssetWriter with HEVC encoding
/// Thread-safe implementation that can receive frames from multiple capture queues
final class MediaWriter: @unchecked Sendable {
    private let logger = Logger(subsystem: "MeetingRecorder", category: "MediaWriter")

    // Asset writer components
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    // Synchronization
    private let writerQueue = DispatchQueue(label: "com.meetingrecorder.mediawriter")
    private let stateLock = NSLock()

    // Configuration
    private let outputURL: URL
    private let videoWidth: Int
    private let videoHeight: Int

    // State tracking
    private var _isRecording = false
    private var sessionStartTime: CMTime?
    private var hasWrittenFirstVideoFrame = false
    private var hasWrittenFirstAudioFrame = false

    private var isRecording: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isRecording
        }
        set {
            stateLock.lock()
            _isRecording = newValue
            stateLock.unlock()
        }
    }

    /// Initialize the media writer
    /// - Parameters:
    ///   - outputURL: URL where the recording will be saved
    ///   - videoWidth: Width of the video in pixels
    ///   - videoHeight: Height of the video in pixels
    init(outputURL: URL, videoWidth: Int, videoHeight: Int) {
        self.outputURL = outputURL
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
    }

    /// Starts the media writer with HEVC video and AAC audio
    func startWriting() throws {
        guard !isRecording else {
            logger.warning("Already recording")
            throw MediaWriterError.alreadyRecording
        }

        // Ensure output directory exists
        let outputDir = outputURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: outputDir.path) {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        // Create asset writer for MP4 container
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        guard let assetWriter = assetWriter else {
            throw MediaWriterError.setupFailed("Asset writer creation failed")
        }

        // Setup HEVC video input
        try setupVideoInput(writer: assetWriter)

        // Setup AAC audio input
        try setupAudioInput(writer: assetWriter)

        // Start writing session
        guard assetWriter.startWriting() else {
            let error = assetWriter.error?.localizedDescription ?? "Unknown error"
            throw MediaWriterError.setupFailed("Failed to start writing: \(error)")
        }

        // Reset state
        sessionStartTime = nil
        hasWrittenFirstVideoFrame = false
        hasWrittenFirstAudioFrame = false
        isRecording = true

        logger.info("Started media writing to: \(self.outputURL.path)")
    }

    /// Appends a composited video pixel buffer to the recording
    /// - Parameters:
    ///   - pixelBuffer: The composited CVPixelBuffer to write
    ///   - presentationTime: The presentation timestamp for this frame
    func appendVideoPixelBuffer(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        writerQueue.async { [weak self] in
            self?.appendVideoPixelBufferSync(pixelBuffer, presentationTime: presentationTime)
        }
    }

    private func appendVideoPixelBufferSync(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard isRecording,
            let videoInput = videoInput,
            let adaptor = pixelBufferAdaptor,
            let assetWriter = assetWriter
        else {
            return
        }

        // Start session on first frame
        if sessionStartTime == nil {
            sessionStartTime = presentationTime
            assetWriter.startSession(atSourceTime: presentationTime)
            logger.info("Started asset writer session at time: \(presentationTime.seconds)")
        }

        // Wait for input to be ready
        guard videoInput.isReadyForMoreMediaData else {
            logger.debug("Video input not ready, dropping frame")
            return
        }

        // Append pixel buffer with timestamp
        let success = adaptor.append(pixelBuffer, withPresentationTime: presentationTime)

        if success {
            if !hasWrittenFirstVideoFrame {
                hasWrittenFirstVideoFrame = true
                logger.info("Written first video frame")
            }
        } else {
            logger.warning("Failed to append video pixel buffer at time: \(presentationTime.seconds)")
        }
    }

    /// Appends an audio sample buffer to the recording
    /// - Parameter sampleBuffer: The audio CMSampleBuffer to write
    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            self?.appendAudioSampleSync(sampleBuffer)
        }
    }

    private func appendAudioSampleSync(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
            let audioInput = audioInput,
            sessionStartTime != nil  // Only write audio after video session starts
        else {
            return
        }

        guard audioInput.isReadyForMoreMediaData else {
            logger.debug("Audio input not ready, dropping sample")
            return
        }

        let success = audioInput.append(sampleBuffer)

        if success {
            if !hasWrittenFirstAudioFrame {
                hasWrittenFirstAudioFrame = true
                logger.info("Written first audio frame")
            }
        } else {
            logger.warning("Failed to append audio sample buffer")
        }
    }

    /// Finishes writing and saves the file
    /// - Returns: The URL of the saved media file
    func finishWriting() async throws -> URL {
        guard isRecording else {
            throw MediaWriterError.notRecording
        }

        guard let assetWriter = assetWriter else {
            throw MediaWriterError.setupFailed("Asset writer not initialized")
        }

        // Mark inputs as finished on writer queue
        await withCheckedContinuation { continuation in
            writerQueue.async { [weak self] in
                self?.audioInput?.markAsFinished()
                self?.videoInput?.markAsFinished()
                continuation.resume()
            }
        }

        isRecording = false

        // Wait for writing to complete
        return try await withCheckedThrowingContinuation { continuation in
            assetWriter.finishWriting { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: MediaWriterError.setupFailed("Self deallocated"))
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
                    continuation.resume(
                        throwing: MediaWriterError.writingFailed("Unexpected status: \(status.rawValue)")
                    )
                }
            }
        }
    }

    /// Cancels the current writing session
    func cancelWriting() {
        writerQueue.async { [weak self] in
            guard let self = self, self.isRecording else { return }

            self.assetWriter?.cancelWriting()
            self.isRecording = false

            self.logger.info("Cancelled media writing")
        }
    }

    // MARK: - Private Setup Methods

    private func setupVideoInput(writer: AVAssetWriter) throws {
        // HEVC (H.265) compression settings for high quality and efficiency
        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: 8_000_000,  // 8 Mbps for screen recording quality
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoMaxKeyFrameIntervalKey: 60,  // Keyframe every 2 seconds at 30fps
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel
        ]

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        guard let videoInput = videoInput else {
            throw MediaWriterError.setupFailed("Failed to create video input")
        }

        // Create pixel buffer adaptor for efficient CVPixelBuffer writing
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: videoWidth,
            kCVPixelBufferHeightKey as String: videoHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        } else {
            throw MediaWriterError.setupFailed("Cannot add video input to asset writer")
        }

        logger.info("Configured HEVC video input: \(self.videoWidth)x\(self.videoHeight)")
    }

    private func setupAudioInput(writer: AVAssetWriter) throws {
        // AAC audio settings matching capture configuration
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,  // Match SCStream sample rate
            AVNumberOfChannelsKey: 2,  // Stereo for system + mic separation
            AVEncoderBitRateKey: 128_000  // 128 kbps
        ]

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true

        guard let audioInput = audioInput else {
            throw MediaWriterError.setupFailed("Failed to create audio input")
        }

        if writer.canAdd(audioInput) {
            writer.add(audioInput)
        } else {
            throw MediaWriterError.setupFailed("Cannot add audio input to asset writer")
        }

        logger.info("Configured AAC audio input: 48kHz stereo")
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
