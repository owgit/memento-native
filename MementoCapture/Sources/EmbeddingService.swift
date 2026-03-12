import Foundation
import NaturalLanguage
import Accelerate

/// Local embedding service using Apple NaturalLanguage framework.
/// Uses language-aware model selection to improve multilingual matching quality.
class EmbeddingService {
    struct EmbeddingResult {
        let vector: [Float]
        let language: NLLanguage
        let revision: Int
    }

    static let supportedLanguages: [NLLanguage] = [.english, .swedish, .german, .french, .spanish]

    private let sentenceEmbeddings: [NLLanguage: NLEmbedding]
    private let availableLanguages: [NLLanguage]
    let dimensions: Int

    init() {
        var loadedEmbeddings: [NLLanguage: NLEmbedding] = [:]

        for language in Self.supportedLanguages {
            if let embedding = NLEmbedding.sentenceEmbedding(for: language) {
                loadedEmbeddings[language] = embedding
            }
        }

        sentenceEmbeddings = loadedEmbeddings
        availableLanguages = Self.supportedLanguages.filter { loadedEmbeddings[$0] != nil }
        dimensions = availableLanguages
            .compactMap { loadedEmbeddings[$0]?.dimension }
            .first ?? 512

        if availableLanguages.isEmpty {
            print("⚠️ Sentence embedding not available")
        } else {
            let labels = availableLanguages.map(\.rawValue).joined(separator: ", ")
            print("🧠 Sentence embeddings loaded: \(labels)")
        }
    }

    /// Generate an embedding vector for text using the best matching language model.
    func embed(_ text: String, preferredLanguage: NLLanguage? = nil) -> EmbeddingResult? {
        let cleanText = normalizedEmbeddingText(text)
        guard !cleanText.isEmpty else { return nil }

        for language in candidateLanguages(for: cleanText, preferredLanguage: preferredLanguage) {
            guard let embedding = sentenceEmbeddings[language],
                  let vector = embedding.vector(for: cleanText) else {
                continue
            }

            var floatVector = vector.map(Float.init)
            normalize(&floatVector)
            return EmbeddingResult(vector: floatVector, language: language, revision: embedding.revision)
        }

        return nil
    }

    /// Build query vectors for all plausible language candidates so search can compare
    /// against embeddings created with different language models.
    func queryEmbeddings(for text: String, preferredLanguage: NLLanguage? = nil) -> [NLLanguage: [Int8]] {
        queryEmbeddingResults(for: text, preferredLanguage: preferredLanguage)
            .mapValues { quantize($0.vector) }
    }

    func queryEmbeddingResults(for text: String, preferredLanguage: NLLanguage? = nil) -> [NLLanguage: EmbeddingResult] {
        let cleanText = normalizedEmbeddingText(text)
        guard !cleanText.isEmpty else { return [:] }

        var results: [NLLanguage: EmbeddingResult] = [:]
        for language in candidateLanguages(for: cleanText, preferredLanguage: preferredLanguage) {
            guard let embedding = sentenceEmbeddings[language],
                  let vector = embedding.vector(for: cleanText) else {
                continue
            }

            var floatVector = vector.map(Float.init)
            normalize(&floatVector)
            results[language] = EmbeddingResult(
                vector: floatVector,
                language: language,
                revision: embedding.revision
            )
        }

        return results
    }

    private func normalizedEmbeddingText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(1200)
            .description
    }

    private func candidateLanguages(for text: String, preferredLanguage: NLLanguage?) -> [NLLanguage] {
        guard !availableLanguages.isEmpty else { return [] }

        var candidates: [NLLanguage] = []

        if let preferredLanguage, sentenceEmbeddings[preferredLanguage] != nil {
            candidates.append(preferredLanguage)
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        if let dominant = recognizer.dominantLanguage,
           sentenceEmbeddings[dominant] != nil {
            candidates.append(dominant)
        }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
            .sorted { lhs, rhs in lhs.value > rhs.value }
            .map(\.key)

        for language in hypotheses where sentenceEmbeddings[language] != nil {
            candidates.append(language)
        }

        candidates.append(contentsOf: availableLanguages)

        var deduplicated: [NLLanguage] = []
        var seen = Set<NLLanguage>()
        for language in candidates where seen.insert(language).inserted {
            deduplicated.append(language)
        }

        return deduplicated
    }

    /// Normalize vector to unit length (L2 norm).
    private func normalize(_ vector: inout [Float]) {
        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
        norm = sqrt(norm)
        if norm > 0 {
            var scale = 1.0 / norm
            vDSP_vsmul(vector, 1, &scale, &vector, 1, vDSP_Length(vector.count))
        }
    }

    /// SIMD-accelerated cosine similarity (vectors should be normalized).
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }

    // MARK: - Quantization (8x smaller storage)

    /// Quantize float32 vector to int8 (8x compression).
    func quantize(_ vector: [Float]) -> [Int8] {
        var maxVal: Float = 0
        vDSP_maxmgv(vector, 1, &maxVal, vDSP_Length(vector.count))

        let scale = maxVal > 0 ? 127.0 / maxVal : 1.0
        return vector.map { Int8(clamping: Int(($0 * scale).rounded())) }
    }

    /// Dequantize int8 back to float32.
    func dequantize(_ quantized: [Int8], scale: Float = 1.0 / 127.0) -> [Float] {
        quantized.map { Float($0) * scale }
    }

    /// Cosine similarity for quantized vectors (approximate but fast).
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

    /// Serialize float vector to Data.
    func vectorToData(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Deserialize Data to float vector.
    func dataToVector(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// Serialize quantized vector to Data (8x smaller).
    func quantizedToData(_ vector: [Int8]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Deserialize Data to quantized vector.
    func dataToQuantized(_ data: Data) -> [Int8] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Int8.self)) }
    }
}
