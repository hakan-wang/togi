import Foundation
import NaturalLanguage

/// Produces on-device sentence embeddings. Phase 2 ships Apple's `NLEmbedding`
/// (zero-dependency, nothing leaves the device); EmbeddingGemma-300M (CoreML) swaps in
/// later behind this same protocol.
protocol EmbeddingService {
    var dimension: Int { get }
    func embed(_ text: String) -> [Float]?
}

/// Apple `NLEmbedding` sentence vectors (512-dim, English). Fully local.
final class AppleSentenceEmbedding: EmbeddingService {
    private let embedding: NLEmbedding?

    init(language: NLLanguage = .english) {
        self.embedding = NLEmbedding.sentenceEmbedding(for: language)
    }

    var dimension: Int { embedding?.dimension ?? 0 }

    func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let embedding, let vector = embedding.vector(for: trimmed) else { return nil }
        return vector.map { Float($0) }
    }
}
