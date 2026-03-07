import Foundation
import AVFoundation
import CoreGraphics
import VideoToolbox

enum VideoEncoderError: LocalizedError {
    case writerUnavailable
    case appendFailed(status: AVAssetWriter.Status, details: String?)
    case finalizeFailed(status: AVAssetWriter.Status, details: String?)

    var errorDescription: String? {
        switch self {
        case .writerUnavailable:
            return "Video writer is unavailable."
        case let .appendFailed(status, details):
            return "Failed to append frame (status: \(Self.statusLabel(for: status)))\(Self.suffix(details))."
        case let .finalizeFailed(status, details):
            return "Failed to finalize video (status: \(Self.statusLabel(for: status)))\(Self.suffix(details))."
        }
    }

    private static func statusLabel(for status: AVAssetWriter.Status) -> String {
        switch status {
        case .unknown: return "unknown"
        case .writing: return "writing"
        case .completed: return "completed"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        @unknown default: return "unknown"
        }
    }

    private static func suffix(_ details: String?) -> String {
        guard let details, !details.isEmpty else { return "" }
        return ": \(details)"
    }
}

/// Hardware-accelerated video encoder using VideoToolbox
class VideoEncoder {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private let outputDirectory: URL
    private let framesPerVideo: Int
    private let frameDuration: TimeInterval
    private var currentVideoIndex: Int = 0
    private var frameIndex: Int = 0
    private var isInitialized = false
    
    // Video settings - will be set from first frame
    private var width: Int = 0
    private var height: Int = 0
    
    init(outputDirectory: URL, framesPerVideo: Int, frameDuration: TimeInterval) {
        self.outputDirectory = outputDirectory
        self.framesPerVideo = framesPerVideo
        self.frameDuration = frameDuration
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
            // High bitrate for crisp screen text
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,  // 8 Mbps for sharp text
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoMaxKeyFrameIntervalKey: 1  // Every frame is keyframe for quality
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

    @discardableResult
    func addFrame(_ image: CGImage) throws -> Bool {
        // Initialize on first frame
        if !isInitialized {
            initializeWriter(width: image.width, height: image.height, index: currentVideoIndex)
        }

        guard let assetWriter,
              let videoInput = videoInput,
              let pixelBufferAdaptor = pixelBufferAdaptor else {
            throw VideoEncoderError.writerUnavailable
        }

        guard videoInput.isReadyForMoreMediaData else {
            if assetWriter.status == .failed || assetWriter.status == .cancelled {
                throw VideoEncoderError.appendFailed(
                    status: assetWriter.status,
                    details: assetWriter.error?.localizedDescription
                )
            }
            print("⚠️ Video input not ready")
            return false
        }

        // Create pixel buffer
        guard let pixelBuffer = createPixelBuffer(from: image) else {
            print("⚠️ Failed to create pixel buffer")
            return false
        }

        // Each MP4 starts from a local zero-based timeline so frame extraction stays stable.
        let presentationTime = CMTime(seconds: Double(frameIndex) * frameDuration, preferredTimescale: 600)

        // Append frame
        if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            frameIndex += 1
            return frameIndex >= framesPerVideo
        } else {
            throw VideoEncoderError.appendFailed(
                status: assetWriter.status,
                details: assetWriter.error?.localizedDescription
            )
        }
    }

    func finalize() async throws {
        guard let videoInput = videoInput,
              let assetWriter = assetWriter else { return }

        let finalizedVideoIndex = currentVideoIndex
        videoInput.markAsFinished()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            assetWriter.finishWriting {
                continuation.resume()
            }
        }

        defer { resetWriterState() }

        guard assetWriter.status == .completed else {
            throw VideoEncoderError.finalizeFailed(
                status: assetWriter.status,
                details: assetWriter.error?.localizedDescription
            )
        }

        print("✅ Finalized video \(finalizedVideoIndex).mp4")
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

    private func resetWriterState() {
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        isInitialized = false
    }
}
