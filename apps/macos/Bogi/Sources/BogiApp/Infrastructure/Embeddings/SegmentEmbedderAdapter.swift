import Foundation

/// Integration glue: bridges the embeddings pipeline (`EmbeddingService` +
/// `VectorIndex`) to the judge's `SegmentEmbedder` seam so a freshly-judged
/// segment's description becomes semantically searchable.
///
/// The judge depends only on the `SegmentEmbedder` protocol (declared in
/// `Features/Judge/JudgeService.swift`); this concrete adapter is wired in
/// `AppEnvironment`. Embedding is best-effort — failures propagate to the judge,
/// which already swallows them per-segment so judging never blocks on search.
final class SegmentEmbedderAdapter: SegmentEmbedder {
    private let embedding: EmbeddingService
    private let index: VectorIndex

    init(embedding: EmbeddingService, index: VectorIndex) {
        self.embedding = embedding
        self.index = index
    }

    func embed(segmentId: String, text: String) async throws {
        let vector = try await embedding.embed(text)
        try await index.upsert(segmentId: segmentId, embedding: vector)
    }
}
