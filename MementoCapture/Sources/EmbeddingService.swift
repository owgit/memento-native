import Foundation
import NaturalLanguage
import Accelerate

/// Local embedding service using Apple NaturalLanguage framework
/// Optimized with quantization and SIMD operations
class EmbeddingService {
    private var sentenceEmbedding: NLEmbedding?
    let dimensions = 512  // NL sentence embedding dimension
    
    init() {
        // Load sentence embedding model (works offline)
        if let embedding = NLEmbedding.sentenceEmbedding(for: .english) {
            sentenceEmbedding = embedding
            print("🧠 Sentence embedding loaded (512-dim)")
        } else {
            print("⚠️ Sentence embedding not available")
        }
    }
    
    /// Generate embedding vector for text
    func embed(_ text: String) -> [Float]? {
        guard let embedding = sentenceEmbedding else { return nil }
        
        // Clean and truncate text
        let cleanText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(1000)
        
        guard !cleanText.isEmpty else { return nil }
        
        // Get vector and normalize
        if let vector = embedding.vector(for: String(cleanText)) {
            var floatVector = vector.map { Float($0) }
            normalize(&floatVector)
            return floatVector
        }
        
        return nil
    }
    
    /// Normalize vector to unit length (L2 norm)
    private func normalize(_ vector: inout [Float]) {
        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
        norm = sqrt(norm)
        if norm > 0 {
            var scale = 1.0 / norm
            vDSP_vsmul(vector, 1, &scale, &vector, 1, vDSP_Length(vector.count))
        }
    }
    
    /// SIMD-accelerated cosine similarity (vectors should be normalized)
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }
    
    // MARK: - Quantization (8x smaller storage)
    
    /// Quantize float32 vector to int8 (8x compression)
    func quantize(_ vector: [Float]) -> [Int8] {
        // Find scale factor
        var maxVal: Float = 0
        vDSP_maxmgv(vector, 1, &maxVal, vDSP_Length(vector.count))
        
        let scale = maxVal > 0 ? 127.0 / maxVal : 1.0
        
        return vector.map { Int8(clamping: Int(($0 * scale).rounded())) }
    }
    
    /// Dequantize int8 back to float32
    func dequantize(_ quantized: [Int8], scale: Float = 1.0/127.0) -> [Float] {
        return quantized.map { Float($0) * scale }
    }
    
    /// Cosine similarity for quantized vectors (approximate but fast)
    func cosineSimilarityQuantized(_ a: [Int8], _ b: [Int8]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dotProduct: Int32 = 0
        var normA: Int32 = 0
        var normB: Int32 = 0
        
        for i in 0..<a.count {
            let ai = Int32(a[i])
            let bi = Int32(b[i])
            dotProduct += ai * bi
            normA += ai * ai
            normB += bi * bi
        }
        
        let denom = sqrt(Float(normA)) * sqrt(Float(normB))
        return denom > 0 ? Float(dotProduct) / denom : 0
    }
    
    // MARK: - Serialization
    
    /// Serialize float vector to Data
    func vectorToData(_ vector: [Float]) -> Data {
        return vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    
    /// Deserialize Data to float vector
    func dataToVector(_ data: Data) -> [Float] {
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
    
    /// Serialize quantized vector to Data (8x smaller)
    func quantizedToData(_ vector: [Int8]) -> Data {
        return vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    
    /// Deserialize Data to quantized vector
    func dataToQuantized(_ data: Data) -> [Int8] {
        return data.withUnsafeBytes { Array($0.bindMemory(to: Int8.self)) }
    }
}

