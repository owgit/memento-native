import Foundation
import NaturalLanguage
import Accelerate

/// Local embedding service using Apple NaturalLanguage framework.
/// Uses language-aware model selection to improve multilingual matching quality.
final class EmbeddingService {
    struct EmbeddingResult {
        let vector: [Float]
        let language: NLLanguage
        let revision: Int
    }

    static let supportedLanguages: [NLLanguage] = [.english, .swedish, .german, .french, .spanish]

    private let sentenceEmbeddings: [NLLanguage: NLEmbedding]
    private let availableLanguages: [NLLanguage]

    init() {
        var loadedEmbeddings: [NLLanguage: NLEmbedding] = [:]

        for language in Self.supportedLanguages {
            if let embedding = NLEmbedding.sentenceEmbedding(for: language) {
                loadedEmbeddings[language] = embedding
            }
        }

        sentenceEmbeddings = loadedEmbeddings
        availableLanguages = Self.supportedLanguages.filter { loadedEmbeddings[$0] != nil }

        if availableLanguages.isEmpty {
            AppLog.warning("⚠️ Sentence embedding not available")
        } else {
            let labels = availableLanguages.map(\.rawValue).joined(separator: ", ")
            AppLog.info("🧠 Sentence embeddings loaded: \(labels)")
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

    // MARK: - Quantization (8x smaller storage)

    /// Quantize float32 vector to int8 (8x compression).
    func quantize(_ vector: [Float]) -> [Int8] {
        var maxVal: Float = 0
        vDSP_maxmgv(vector, 1, &maxVal, vDSP_Length(vector.count))

        let scale = maxVal > 0 ? 127.0 / maxVal : 1.0
        return vector.map { Int8(clamping: Int(($0 * scale).rounded())) }
    }

    /// Serialize quantized vector to Data (8x smaller).
    func quantizedToData(_ vector: [Int8]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
