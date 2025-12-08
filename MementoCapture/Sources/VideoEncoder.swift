import Foundation
import AVFoundation
import CoreGraphics
import VideoToolbox

/// Hardware-accelerated video encoder using VideoToolbox
class VideoEncoder {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private let outputDirectory: URL
    private let framesPerVideo: Int
    private var currentVideoIndex: Int = 0
    private var frameIndex: Int = 0
    private var isInitialized = false
    
    // Video settings - will be set from first frame
    private var width: Int = 0
    private var height: Int = 0
    
    init(outputDirectory: URL, framesPerVideo: Int) {
        self.outputDirectory = outputDirectory
        self.framesPerVideo = framesPerVideo
        // Don't start video yet - wait for first frame to get dimensions
    }
    
    private func initializeWriter(width: Int, height: Int, index: Int) {
        self.width = width
        self.height = height
        currentVideoIndex = index
        frameIndex = 0
        
        let outputURL = outputDirectory.appendingPathComponent("\(index).mp4")
        
        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)
        
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            
            // Video settings - use H.264 with hardware acceleration
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoAllowFrameReorderingKey: false
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput!,
                sourcePixelBufferAttributes: attrs
            )
            
            if assetWriter!.canAdd(videoInput!) {
                assetWriter!.add(videoInput!)
            }
            
            assetWriter!.startWriting()
            assetWriter!.startSession(atSourceTime: .zero)
            
            isInitialized = true
            print("🎥 Started video \(index).mp4 (\(width)x\(height))")
            
        } catch {
            print("⚠️ Failed to create video writer: \(error)")
        }
    }
    
    func startNewVideo(index: Int) {
        if isInitialized && width > 0 && height > 0 {
            initializeWriter(width: width, height: height, index: index)
        } else {
            currentVideoIndex = index
        }
    }
    
    func addFrame(_ image: CGImage, frameIndex globalFrameIndex: Int) {
        // Initialize on first frame
        if !isInitialized {
            initializeWriter(width: image.width, height: image.height, index: currentVideoIndex)
        }
        
        guard let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else {
            print("⚠️ Video input not ready")
            return
        }
        
        // Create pixel buffer
        guard let pixelBuffer = createPixelBuffer(from: image) else {
            print("⚠️ Failed to create pixel buffer")
            return
        }
        
        // Calculate presentation time
        let presentationTime = CMTime(seconds: Double(frameIndex) * 2.0, preferredTimescale: 600)
        
        // Append frame
        if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            frameIndex += 1
        } else {
            print("⚠️ Failed to append frame")
        }
    }
    
    func finalize() {
        guard let videoInput = videoInput,
              let assetWriter = assetWriter else { return }
        
        videoInput.markAsFinished()
        
        let semaphore = DispatchSemaphore(value: 0)
        assetWriter.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()
        
        print("✅ Finalized video \(currentVideoIndex).mp4")
        
        self.assetWriter = nil
        self.videoInput = nil
        self.pixelBufferAdaptor = nil
    }
    
    private func createPixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let width = image.width
        let height = image.height
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
}
