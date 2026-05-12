import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import OSLog

/// Handles real-time video compositing using CoreImage for Picture-in-Picture rendering
/// Composites webcam video overlay onto screen recording frames
/// Thread-safe through internal synchronization - not an actor to allow synchronous
/// frame processing from nonisolated capture callbacks
final class VideoCompositor: @unchecked Sendable {
    private let logger = Logger(subsystem: "MeetingRecorder", category: "VideoCompositor")

    // Synchronization for thread-safe access
    private let lock = NSLock()

    // CoreImage context with Metal acceleration
    private let ciContext: CIContext

    // Configuration
    private let pipScale: CGFloat
    private let pipPadding: CGFloat
    private let pipCornerRadius: CGFloat

    // Cached webcam frame for compositing (latest available)
    private var _latestWebcamFrame: CIImage?
    private var _latestWebcamTimestamp: CMTime = .invalid

    // Output pixel buffer pool for efficient memory reuse
    private var _pixelBufferPool: CVPixelBufferPool?
    private var _outputWidth: Int = 0
    private var _outputHeight: Int = 0

    private var latestWebcamFrame: CIImage? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _latestWebcamFrame
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _latestWebcamFrame = newValue
        }
    }

    private var latestWebcamTimestamp: CMTime {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _latestWebcamTimestamp
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _latestWebcamTimestamp = newValue
        }
    }

    private var pixelBufferPool: CVPixelBufferPool? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _pixelBufferPool
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _pixelBufferPool = newValue
        }
    }

    private var outputWidth: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _outputWidth
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _outputWidth = newValue
        }
    }

    private var outputHeight: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _outputHeight
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _outputHeight = newValue
        }
    }

    /// Initialize the video compositor with Metal-accelerated CoreImage context
    /// - Parameters:
    ///   - pipScale: Scale factor for PiP overlay (0.0-1.0), default 0.2 (20%)
    ///   - pipPadding: Padding from screen edges in pixels
    ///   - pipCornerRadius: Corner radius for PiP window
    init(pipScale: CGFloat = 0.2, pipPadding: CGFloat = 20, pipCornerRadius: CGFloat = 12) {
        // Create Metal-accelerated CIContext for optimal performance
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            let workingColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            self.ciContext = CIContext(
                mtlDevice: metalDevice,
                options: [
                    .workingColorSpace: workingColorSpace,
                    .cacheIntermediates: false
                ])
            logger.info("VideoCompositor initialized with Metal device: \(metalDevice.name)")
        } else {
            self.ciContext = CIContext(options: [
                .useSoftwareRenderer: false,
                .cacheIntermediates: false
            ])
            logger.warning("Metal device not available, using default CIContext")
        }

        self.pipScale = pipScale
        self.pipPadding = pipPadding
        self.pipCornerRadius = pipCornerRadius
    }

    /// Updates the cached webcam frame for compositing
    /// - Parameters:
    ///   - sampleBuffer: The webcam video sample buffer
    func updateWebcamFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            logger.warning("Failed to get pixel buffer from webcam sample")
            return
        }

        latestWebcamFrame = CIImage(cvPixelBuffer: pixelBuffer)
        latestWebcamTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    }

    /// Composites the screen frame with the webcam overlay
    /// - Parameters:
    ///   - screenBuffer: The screen capture sample buffer
    /// - Returns: A new CVPixelBuffer with the composited frame, or nil on failure
    func composite(screenBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let screenPixelBuffer = CMSampleBufferGetImageBuffer(screenBuffer) else {
            logger.warning("Failed to get pixel buffer from screen sample")
            return nil
        }

        let screenImage = CIImage(cvPixelBuffer: screenPixelBuffer)
        let screenExtent = screenImage.extent

        // Ensure pixel buffer pool is configured for output dimensions
        let width = Int(screenExtent.width)
        let height = Int(screenExtent.height)

        if width != outputWidth || height != outputHeight {
            configurePixelBufferPool(width: width, height: height)
        }

        // Get output buffer from pool
        guard let outputBuffer = createOutputPixelBuffer() else {
            logger.error("Failed to create output pixel buffer")
            return nil
        }

        // Composite webcam onto screen if available
        let compositedImage: CIImage
        if let webcamImage = latestWebcamFrame {
            compositedImage = compositeImages(screen: screenImage, webcam: webcamImage)
        } else {
            compositedImage = screenImage
        }

        // Render to output buffer
        ciContext.render(compositedImage, to: outputBuffer)

        return outputBuffer
    }

    /// Composites webcam image onto screen image with PiP positioning
    private func compositeImages(screen: CIImage, webcam: CIImage) -> CIImage {
        let screenExtent = screen.extent
        let webcamExtent = webcam.extent

        // Calculate PiP dimensions (maintain aspect ratio)
        let targetWidth = screenExtent.width * pipScale
        let webcamAspect = webcamExtent.width / webcamExtent.height
        let targetHeight = targetWidth / webcamAspect

        // Scale webcam to PiP size using Lanczos for quality
        let scaleX = targetWidth / webcamExtent.width
        let scaleY = targetHeight / webcamExtent.height

        guard
            let scaledWebcam =
                webcam
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .applyingFilter(
                    "CILanczosScaleTransform",
                    parameters: [
                        kCIInputScaleKey: scaleX,
                        kCIInputAspectRatioKey: 1.0
                    ]) as CIImage?
        else {
            return screen
        }

        // Apply rounded corners to PiP
        let roundedWebcam = applyRoundedCorners(to: scaledWebcam, radius: pipCornerRadius * scaleX)

        // Position in bottom-right corner with padding
        let pipX = screenExtent.width - targetWidth - pipPadding
        let pipY = pipPadding  // Bottom of screen (CoreImage origin is bottom-left)

        let translatedWebcam = roundedWebcam.transformed(
            by: CGAffineTransform(translationX: pipX, y: pipY)
        )

        // Composite using source-over
        return translatedWebcam.composited(over: screen)
    }

    /// Applies rounded corners to an image using a rounded rectangle mask
    private func applyRoundedCorners(to image: CIImage, radius: CGFloat) -> CIImage {
        let extent = image.extent

        // Create rounded rectangle path
        let roundedRect = CGRect(
            x: extent.origin.x,
            y: extent.origin.y,
            width: extent.width,
            height: extent.height
        )

        // Use CIFilter to create rounded corners
        guard let roundedRectGenerator = CIFilter(name: "CIRoundedRectangleGenerator") else {
            return image
        }

        roundedRectGenerator.setValue(CIVector(cgRect: roundedRect), forKey: "inputExtent")
        roundedRectGenerator.setValue(radius, forKey: "inputRadius")
        roundedRectGenerator.setValue(CIColor.white, forKey: "inputColor")

        guard let maskImage = roundedRectGenerator.outputImage else {
            return image
        }

        // Apply mask using blend with mask
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return image
        }

        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? image
    }

    /// Configures the pixel buffer pool for the given dimensions
    private func configurePixelBufferPool(width: Int, height: Int) {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        )

        if status == kCVReturnSuccess, let pool = pool {
            self.pixelBufferPool = pool
            self.outputWidth = width
            self.outputHeight = height
            logger.info("Created pixel buffer pool: \(width)x\(height)")
        } else {
            logger.error("Failed to create pixel buffer pool: \(status)")
        }
    }

    /// Creates an output pixel buffer from the pool
    private func createOutputPixelBuffer() -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else {
            logger.error("Pixel buffer pool not initialized")
            return nil
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)

        if status != kCVReturnSuccess {
            logger.error("Failed to create pixel buffer from pool: \(status)")
            return nil
        }

        return pixelBuffer
    }

    /// Clears the cached webcam frame
    func clearWebcamFrame() {
        latestWebcamFrame = nil
        latestWebcamTimestamp = .invalid
    }

    /// Releases resources
    func shutdown() {
        pixelBufferPool = nil
        latestWebcamFrame = nil
        outputWidth = 0
        outputHeight = 0
        logger.info("VideoCompositor shutdown")
    }
}
