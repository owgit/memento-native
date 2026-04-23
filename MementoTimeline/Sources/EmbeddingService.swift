import Foundation
import NaturalLanguage
import Accelerate

/// Local embedding service using Apple NaturalLanguage framework.
/// Loads system language + English at startup; other supported languages are lazy-loaded
/// on first encounter (e.g. when a search query is detected as another language).
final class EmbeddingService {
    struct EmbeddingResult {
        let vector: [Float]
        let language: NLLanguage
        let revision: Int
    }

    static let supportedLanguages: [NLLanguage] = [.english, .swedish, .german, .french, .spanish]

    private var sentenceEmbeddings: [NLLanguage: NLEmbedding] = [:]

    init() {
        let initialLanguages = Self.languagesToLoadAtStartup()
        for language in initialLanguages {
            if let model = NLEmbedding.sentenceEmbedding(for: language) {
                sentenceEmbeddings[language] = model
            }
        }

        if sentenceEmbeddings.isEmpty {
            AppLog.warning("⚠️ Sentence embedding not available")
        } else {
            let labels = sentenceEmbeddings.keys.map(\.rawValue).sorted().joined(separator: ", ")
            AppLog.info("🧠 Sentence embeddings loaded: \(labels)")
        }
    }

    func queryEmbeddingResults(for text: String, preferredLanguage: NLLanguage? = nil) -> [NLLanguage: EmbeddingResult] {
        let cleanText = normalizedEmbeddingText(text)
        guard !cleanText.isEmpty else { return [:] }

        var results: [NLLanguage: EmbeddingResult] = [:]
        for language in candidateLanguages(for: cleanText, preferredLanguage: preferredLanguage) {
            guard let model = embedding(for: language),
                  let vector = model.vector(for: cleanText) else {
                continue
            }

            var floatVector = vector.map(Float.init)
            normalize(&floatVector)
            results[language] = EmbeddingResult(
                vector: floatVector,
                language: language,
                revision: model.revision
            )
        }

        return results
    }

    // MARK: - Lazy model loading

    private func embedding(for language: NLLanguage) -> NLEmbedding? {
        if let existing = sentenceEmbeddings[language] { return existing }
        guard Self.supportedLanguages.contains(language) else { return nil }
        guard let model = NLEmbedding.sentenceEmbedding(for: language) else { return nil }
        sentenceEmbeddings[language] = model
        AppLog.info("🧠 Lazy-loaded embedding: \(language.rawValue)")
        return model
    }

    private static func languagesToLoadAtStartup() -> [NLLanguage] {
        var languages: Set<NLLanguage> = [.english]
        let systemCode = Locale.current.language.languageCode?.identifier ?? "en"
        let systemLanguage = NLLanguage(rawValue: systemCode)
        if supportedLanguages.contains(systemLanguage) {
            languages.insert(systemLanguage)
        }
        return Array(languages)
    }

    // MARK: - Language detection

    private func normalizedEmbeddingText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(1200)
            .description
    }

    private func candidateLanguages(for text: String, preferredLanguage: NLLanguage?) -> [NLLanguage] {
        var candidates: [NLLanguage] = []

        if let preferredLanguage, Self.supportedLanguages.contains(preferredLanguage) {
            candidates.append(preferredLanguage)
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        if let dominant = recognizer.dominantLanguage,
           Self.supportedLanguages.contains(dominant) {
            candidates.append(dominant)
        }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
            .sorted { lhs, rhs in lhs.value > rhs.value }
            .map(\.key)

        for language in hypotheses where Self.supportedLanguages.contains(language) {
            candidates.append(language)
        }

        // Fallback: already-loaded languages
        candidates.append(contentsOf: sentenceEmbeddings.keys)

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

    /// Deserialize Data to float vector.
    func dataToVector(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    /// Deserialize Data to quantized vector.
    func dataToQuantized(_ data: Data) -> [Int8] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Int8.self)) }
    }
}
