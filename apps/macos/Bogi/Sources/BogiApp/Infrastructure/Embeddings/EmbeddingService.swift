import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Target dimensionality for every embedding Bogi stores. Matches the
/// `segment_vec vec0(embedding float[256])` table and the EmbeddingGemma
/// Matryoshka-256 truncation. Keep this in sync with `VectorIndex`.
public let bogiEmbeddingDimension = 256

/// Produces a fixed-size (256-dim) on-device embedding for a piece of text.
/// Every implementation runs fully on-device — nothing leaves the machine.
public protocol EmbeddingService: Sendable {
    /// Embeds `text` into a unit-length `bogiEmbeddingDimension`-dimensional
    /// vector. Throws `EmbeddingError` when the text is empty or the model is
    /// unavailable.
    func embed(_ text: String) async throws -> [Float]
}

public enum EmbeddingError: Error, Equatable {
    /// The backing model (CoreML / NaturalLanguage assets) is not available.
    case modelUnavailable
    /// The input was empty or whitespace-only.
    case emptyInput
    /// The model ran but produced no usable vectors.
    case embeddingFailed
}

/// Which on-device embedding implementation to use. Stored as the raw string in
/// `SettingsStore.Key.embedImpl` so it can be flipped without a code change.
public enum EmbeddingImpl: String, CaseIterable, Sendable {
    /// Apple `NLContextualEmbedding` (ships with macOS; the default today).
    case nlContextual = "nl_contextual"
    /// EmbeddingGemma-300M exported to CoreML (future; see `EmbeddingGemmaService`).
    case embeddingGemma = "embedding_gemma"
}

// MARK: - Pure vector helpers (framework-light, unit-testable)

/// Small pure helpers shared by the embedding implementations. Kept free of
/// AppKit / NaturalLanguage so they compile and test anywhere.
enum EmbeddingMath {
    /// Matryoshka-style resize: truncate to the first `dimension` components, or
    /// zero-pad when the source vector is shorter. EmbeddingGemma is trained so
    /// that a truncated prefix is itself a valid (lower-fidelity) embedding.
    static func resize(_ vector: [Float], to dimension: Int) -> [Float] {
        if vector.count == dimension { return vector }
        if vector.count > dimension { return Array(vector.prefix(dimension)) }
        return vector + Array(repeating: Float(0), count: dimension - vector.count)
    }

    /// L2-normalize so cosine distance and the L2 distance sqlite-vec computes
    /// agree on ordering. A zero vector is returned unchanged.
    static func l2Normalized(_ vector: [Float]) -> [Float] {
        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    /// Mean-pool a list of equal-length token vectors into a single vector.
    /// Returns an empty array when there are no tokens.
    static func meanPool(_ vectors: [[Double]]) -> [Float] {
        guard let width = vectors.first?.count, width > 0 else { return [] }
        var sums = [Double](repeating: 0, count: width)
        var counted = 0
        for vector in vectors where vector.count == width {
            for i in 0..<width { sums[i] += vector[i] }
            counted += 1
        }
        guard counted > 0 else { return [] }
        let denom = Double(counted)
        return sums.map { Float($0 / denom) }
    }
}

// MARK: - Impl A: Apple NaturalLanguage (default)

#if canImport(NaturalLanguage)
/// Embeds text with Apple's on-device `NLContextualEmbedding`. The model emits
/// one vector per token; we mean-pool those into a single sentence vector and
/// then truncate/pad to `bogiEmbeddingDimension`. No data leaves the device and
/// no network access is required once the language assets are present.
@available(macOS 14.0, *)
public final class NLContextualEmbeddingService: EmbeddingService {
    private let language: NLLanguage
    private let dimension: Int
    private let embedding: NLContextualEmbedding?
    private let loadLock = NSLock()
    private var didLoad = false

    public init(language: NLLanguage = .english, dimension: Int = bogiEmbeddingDimension) {
        self.language = language
        self.dimension = dimension
        self.embedding = NLContextualEmbedding(language: language)
    }

    public func embed(_ text: String) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingError.emptyInput }
        guard let embedding else { throw EmbeddingError.modelUnavailable }

        try ensureLoaded(embedding)

        let result = try embedding.embeddingResult(for: trimmed, language: language)
        var tokenVectors: [[Double]] = []
        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            tokenVectors.append(vector)
            return true
        }
        let pooled = EmbeddingMath.meanPool(tokenVectors)
        guard !pooled.isEmpty else { throw EmbeddingError.embeddingFailed }
        return EmbeddingMath.l2Normalized(EmbeddingMath.resize(pooled, to: dimension))
    }

    /// Loads the language assets exactly once. `load()` is required before
    /// `embeddingResult(for:language:)`; calling it repeatedly is wasteful, so
    /// we guard it behind a lock.
    private func ensureLoaded(_ embedding: NLContextualEmbedding) throws {
        loadLock.lock()
        defer { loadLock.unlock() }
        guard !didLoad else { return }
        try embedding.load()
        didLoad = true
    }
}
#endif

// MARK: - Impl B: EmbeddingGemma (future, CoreML)

/// FUTURE on-device model: **EmbeddingGemma-300M** exported to CoreML, producing
/// 256-dim Matryoshka embeddings. This is a deliberate stub — it conforms to
/// `EmbeddingService` so it can be selected today via the `embed_impl` feature
/// flag, but it has no bundled `.mlmodelc` yet and therefore throws
/// `.modelUnavailable`. Callers should fall back to `NLContextualEmbeddingService`
/// (see `EmbeddingServiceFactory`). Replace the body of `embed(_:)` with a
/// `MLModel` prediction + Matryoshka-256 truncation once the converted model
/// ships in the app bundle.
public final class EmbeddingGemmaService: EmbeddingService {
    private let dimension: Int

    public init(dimension: Int = bogiEmbeddingDimension) {
        self.dimension = dimension
    }

    public func embed(_ text: String) async throws -> [Float] {
        // No converted CoreML model is bundled yet. Intentionally unavailable so
        // the factory transparently falls back to the NaturalLanguage impl.
        throw EmbeddingError.modelUnavailable
    }
}

// MARK: - Factory

/// Selects an `EmbeddingService` from the `embed_impl` feature flag, defaulting
/// to the always-available NaturalLanguage implementation.
public enum EmbeddingServiceFactory {
    public static func make(impl: EmbeddingImpl) -> EmbeddingService {
        switch impl {
        case .embeddingGemma:
            return EmbeddingGemmaService()
        case .nlContextual:
            #if canImport(NaturalLanguage)
            if #available(macOS 14.0, *) {
                return NLContextualEmbeddingService()
            }
            #endif
            // No NaturalLanguage available (e.g. building off-platform): the
            // Gemma stub stands in and reports `.modelUnavailable`.
            return EmbeddingGemmaService()
        }
    }

    /// Reads the `embed_impl` setting, falling back to `.nlContextual`.
    public static func make(settings: SettingsStore) -> EmbeddingService {
        let impl = settings.string(.embedImpl).flatMap(EmbeddingImpl.init(rawValue:)) ?? .nlContextual
        return make(impl: impl)
    }
}
