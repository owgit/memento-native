import Foundation
import NaturalLanguage
import Accelerate

/// Local embedding service using Apple NaturalLanguage framework.
/// Loads system language + English at startup; other supported languages are lazy-loaded
/// on first encounter (e.g. when OCR detects Spanish text).
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

    /// Generate an embedding vector for text using the best matching language model.
    func embed(_ text: String, preferredLanguage: NLLanguage? = nil) -> EmbeddingResult? {
        let cleanText = normalizedEmbeddingText(text)
        guard !cleanText.isEmpty else { return nil }

        for language in candidateLanguages(for: cleanText, preferredLanguage: preferredLanguage) {
            guard let model = embedding(for: language),
                  let vector = model.vector(for: cleanText) else {
                continue
            }

            var floatVector = vector.map(Float.init)
            normalize(&floatVector)
            return EmbeddingResult(vector: floatVector, language: language, revision: model.revision)
        }

        return nil
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
