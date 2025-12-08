import Foundation
import NaturalLanguage

/// Local embedding service using Apple NaturalLanguage framework
class EmbeddingService {
    private var sentenceEmbedding: NLEmbedding?
    private let dimensions = 512  // NL sentence embedding dimension
    
    init() {
        // Load sentence embedding model (works offline)
        if let embedding = NLEmbedding.sentenceEmbedding(for: .english) {
            sentenceEmbedding = embedding
            print("🧠 Sentence embedding loaded (English)")
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
            .prefix(1000)  // Limit length
        
        guard !cleanText.isEmpty else { return nil }
        
        // Get vector
        if let vector = embedding.vector(for: String(cleanText)) {
            return vector.map { Float($0) }
        }
        
        return nil
    }
    
    /// Find similar texts using cosine similarity
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }
    
    /// Serialize vector to Data for storage
    func vectorToData(_ vector: [Float]) -> Data {
        return vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
    
    /// Deserialize Data back to vector
    func dataToVector(_ data: Data) -> [Float] {
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}
