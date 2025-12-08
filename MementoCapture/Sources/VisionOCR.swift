import Foundation
import Vision
import CoreGraphics

/// Apple Vision-based OCR engine
class VisionOCR {
    
    private let recognitionLevel: VNRequestTextRecognitionLevel
    private let minimumConfidence: Float
    
    init(recognitionLevel: VNRequestTextRecognitionLevel = .fast, minimumConfidence: Float = 0.4) {
        self.recognitionLevel = recognitionLevel
        self.minimumConfidence = minimumConfidence
        print("🍎 Vision OCR initialized (level: \(recognitionLevel == .fast ? "fast" : "accurate"))")
    }
    
    /// Recognize text in image
    func recognizeText(in image: CGImage) async -> [TextBlock] {
        return await withCheckedContinuation { continuation in
            recognizeTextSync(in: image) { results in
                continuation.resume(returning: results)
            }
        }
    }
    
    private func recognizeTextSync(in image: CGImage, completion: @escaping ([TextBlock]) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }
            
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            
            var results: [TextBlock] = []
            
            for observation in observations {
                guard observation.confidence >= self.minimumConfidence,
                      let topCandidate = observation.topCandidates(1).first else {
                    continue
                }
                
                let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                
                // Convert normalized coordinates to pixels
                // Vision uses bottom-left origin, we need top-left
                let boundingBox = observation.boundingBox
                let x = Int(boundingBox.origin.x * width)
                let y = Int((1 - boundingBox.origin.y - boundingBox.size.height) * height)
                let w = Int(boundingBox.size.width * width)
                let h = Int(boundingBox.size.height * height)
                
                results.append(TextBlock(
                    text: text,
                    x: max(0, x),
                    y: max(0, y),
                    width: max(1, w),
                    height: max(1, h),
                    confidence: observation.confidence
                ))
            }
            
            completion(results)
        }
        
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("⚠️ Vision OCR error: \(error)")
            completion([])
        }
    }
}
