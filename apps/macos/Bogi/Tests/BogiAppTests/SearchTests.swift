import XCTest
import GRDB
@testable import BogiApp

/// Tests for the Embeddings + Search module (Phase 2).
///
/// NOTE: The tests that touch `VectorIndex` / `SearchService` exercise the
/// sqlite-vec `vec0` virtual table, which requires the native sqlite-vec
/// extension loaded via `SQLiteVec.initialize()`. That extension is only
/// available at runtime on macOS, so these tests run on a macOS toolchain only;
/// they are not (and cannot be) executed on the Linux CI used for these PRs. The
/// pure-logic tests (`SearchRanker`, `EmbeddingMath`) are framework-light.
final class SearchTests: XCTestCase {

    // MARK: - Fakes / helpers

    /// Deterministic embedder: returns the registered vector for a text, a zero
    /// vector for unknown text, or throws `.modelUnavailable` when configured to
    /// simulate a missing model.
    final class FakeEmbeddingService: EmbeddingService, @unchecked Sendable {
        let vectors: [String: [Float]]
        let dimension: Int
        let unavailable: Bool

        init(vectors: [String: [Float]] = [:], dimension: Int = bogiEmbeddingDimension, unavailable: Bool = false) {
            self.vectors = vectors
            self.dimension = dimension
            self.unavailable = unavailable
        }

        func embed(_ text: String) async throws -> [Float] {
            if unavailable { throw EmbeddingError.modelUnavailable }
            let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw EmbeddingError.emptyInput }
            return vectors[key] ?? [Float](repeating: 0, count: dimension)
        }
    }

    /// A unit-length one-hot vector — distinct indices are equidistant, the same
    /// index has distance 0, so KNN ordering is fully predictable.
    private func oneHot(_ index: Int, dim: Int = bogiEmbeddingDimension) -> [Float] {
        var v = [Float](repeating: 0, count: dim)
        v[index] = 1
        return v
    }

    private func makeSegment(
        id: String,
        subSub: String?,
        category: String? = nil,
        subCategory: String? = nil
    ) -> ActivitySegment {
        ActivitySegment(
            id: id,
            startAt: Date(timeIntervalSince1970: 1_000),
            endAt: Date(timeIntervalSince1970: 2_000),
            minutes: 16,
            plannedBlockId: nil,
            category: category,
            subCategory: subCategory,
            subSub: subSub,
            onTask: true,
            confidence: 0.9,
            judgedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    @discardableResult
    private func insert(_ segment: ActivitySegment, into service: DatabaseService) throws -> ActivitySegment {
        var seg = segment
        try service.dbQueue.write { db in try seg.insert(db) }
        return seg
    }

    // MARK: - Pure: Reciprocal Rank Fusion

    func testReciprocalRankFusionMergesAndRanks() {
        // s2 appears near the top of both lists, so it should win overall.
        let keyword = ["s1", "s2", "s3"]
        let semantic = ["s2", "s4"]
        let fused = SearchRanker.reciprocalRankFusion([keyword, semantic])

        XCTAssertEqual(fused.first, "s2", "id present high in both lists should rank first")
        XCTAssertEqual(Set(fused), ["s1", "s2", "s3", "s4"], "all ids are preserved and de-duplicated")
        // s1 (keyword rank 1 only) outranks s3 (keyword rank 3 only).
        XCTAssertLessThan(fused.firstIndex(of: "s1")!, fused.firstIndex(of: "s3")!)
    }

    func testReciprocalRankFusionStableTieBreak() {
        // Single-element lists where both ids share the same rank-1 score:
        // the one seen first (earlier list) wins deterministically.
        let fused = SearchRanker.reciprocalRankFusion([["a"], ["b"]])
        XCTAssertEqual(fused, ["a", "b"])
    }

    func testReciprocalRankFusionEmptyInputs() {
        XCTAssertEqual(SearchRanker.reciprocalRankFusion([]), [])
        XCTAssertEqual(SearchRanker.reciprocalRankFusion([[], []]), [])
    }

    // MARK: - Pure: FTS query sanitization

    func testFtsQuerySanitization() {
        XCTAssertEqual(SearchRanker.ftsQuery(for: "edit videos"), "\"edit\" OR \"videos\"")
        // Punctuation / FTS operators are stripped, never passed through.
        XCTAssertEqual(SearchRanker.ftsQuery(for: "  e-mail: triage!  "), "\"e\" OR \"mail\" OR \"triage\"")
        XCTAssertEqual(SearchRanker.ftsQuery(for: "   "), "")
        XCTAssertEqual(SearchRanker.ftsQuery(for: "***"), "")
    }

    func testEmbeddableTextOrdersMostSpecificFirst() {
        let seg = makeSegment(id: "s1", subSub: "edited youtube video", category: "work", subCategory: "content")
        XCTAssertEqual(SearchRanker.embeddableText(for: seg), "edited youtube video content work")

        let sparse = makeSegment(id: "s2", subSub: nil, category: "work", subCategory: nil)
        XCTAssertEqual(SearchRanker.embeddableText(for: sparse), "work")
    }

    // MARK: - Pure: embedding math

    func testEmbeddingMathResizeTruncatesAndPads() {
        XCTAssertEqual(EmbeddingMath.resize([1, 2, 3, 4], to: 2), [1, 2])
        XCTAssertEqual(EmbeddingMath.resize([1, 2], to: 4), [1, 2, 0, 0])
        XCTAssertEqual(EmbeddingMath.resize([1, 2, 3], to: 3), [1, 2, 3])
    }

    func testEmbeddingMathL2Normalize() {
        let n = EmbeddingMath.l2Normalized([3, 4])
        XCTAssertEqual(n[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(n[1], 0.8, accuracy: 1e-6)
        XCTAssertEqual(EmbeddingMath.l2Normalized([0, 0]), [0, 0], "zero vector is unchanged")
    }

    func testEmbeddingMathMeanPool() {
        let pooled = EmbeddingMath.meanPool([[0, 2, 4], [2, 4, 6]])
        XCTAssertEqual(pooled, [1, 3, 5])
        XCTAssertEqual(EmbeddingMath.meanPool([]), [])
    }

    // MARK: - VectorIndex round-trip (macOS runtime only)

    func testVectorIndexRoundTripKNN() async throws {
        let index = try VectorIndex(location: .inMemory)
        try await index.upsert(segmentId: "s1", embedding: oneHot(1))
        try await index.upsert(segmentId: "s2", embedding: oneHot(2))
        try await index.upsert(segmentId: "s3", embedding: oneHot(3))

        let neighbors = try await index.knn(query: oneHot(2), k: 3)
        XCTAssertEqual(neighbors.first?.segmentId, "s2", "exact match is the nearest neighbour")
        XCTAssertEqual(neighbors.first?.distance ?? 1, 0, accuracy: 1e-5)
        XCTAssertEqual(Set(neighbors.map(\.segmentId)), ["s1", "s2", "s3"])
    }

    func testVectorIndexUpsertOverwrites() async throws {
        let index = try VectorIndex(location: .inMemory)
        try await index.upsert(segmentId: "s1", embedding: oneHot(1))
        // Re-embed s1 onto a new location; must not create a duplicate row.
        try await index.upsert(segmentId: "s1", embedding: oneHot(5))

        let neighbors = try await index.knn(query: oneHot(5), k: 10)
        XCTAssertEqual(neighbors.map(\.segmentId), ["s1"])
        XCTAssertEqual(neighbors.first?.distance ?? 1, 0, accuracy: 1e-5)
    }

    func testVectorIndexRejectsWrongDimension() async throws {
        let index = try VectorIndex(location: .inMemory)
        do {
            try await index.upsert(segmentId: "s1", embedding: [1, 2, 3])
            XCTFail("expected dimension mismatch to throw")
        } catch {
            XCTAssertEqual(error as? EmbeddingError, .embeddingFailed)
        }
    }

    // MARK: - FTS5 keyword match (macOS runtime only)

    func testFTSKeywordMatch() async throws {
        let db = try DatabaseService(inMemory: true)
        try insert(makeSegment(id: "s1", subSub: "edited youtube videos"), into: db)
        try insert(makeSegment(id: "s2", subSub: "wrote swift code"), into: db)
        try insert(makeSegment(id: "s3", subSub: "answered emails"), into: db)

        let service = SearchService(
            database: db,
            vectorIndex: try VectorIndex(location: .inMemory),
            embedder: FakeEmbeddingService()
        )

        let hits = try await service.keywordSearch("videos", limit: 10)
        XCTAssertEqual(hits, ["s1"], "FTS5 matches the segment whose description contains the term")

        let none = try await service.keywordSearch("kayaking", limit: 10)
        XCTAssertEqual(none, [])
    }

    // MARK: - Hybrid search (macOS runtime only)

    func testHybridSearchMergesKeywordAndSemantic() async throws {
        let db = try DatabaseService(inMemory: true)
        let s1 = try insert(makeSegment(id: "s1", subSub: "edited youtube videos"), into: db)
        let s2 = try insert(makeSegment(id: "s2", subSub: "recorded a screencast"), into: db)
        let s3 = try insert(makeSegment(id: "s3", subSub: "answered emails"), into: db)

        // Map each segment's embeddable text to a distinct one-hot vector, and
        // make the query "videos" semantically closest to s2.
        let embedder = FakeEmbeddingService(vectors: [
            SearchRanker.embeddableText(for: s1): oneHot(1),
            SearchRanker.embeddableText(for: s2): oneHot(2),
            SearchRanker.embeddableText(for: s3): oneHot(3),
            "videos": oneHot(2),
        ])
        let index = try VectorIndex(location: .inMemory)
        let service = SearchService(database: db, vectorIndex: index, embedder: embedder)

        try await service.index(s1)
        try await service.index(s2)
        try await service.index(s3)

        let results = try await service.search("videos", limit: 10)
        let ids = results.map(\.id)

        // Keyword arm surfaces s1 (contains "videos"); semantic arm surfaces s2.
        XCTAssertTrue(ids.contains("s1"))
        XCTAssertTrue(ids.contains("s2"))
        // s1 is rank-1 in the keyword list (seen first) so it leads the fusion.
        XCTAssertEqual(ids.first, "s1")
        // s3 is unrelated by keyword and farthest semantically → ranked last.
        XCTAssertEqual(ids.last, "s3")
    }

    func testSearchFallsBackToKeywordWhenEmbedderUnavailable() async throws {
        let db = try DatabaseService(inMemory: true)
        try insert(makeSegment(id: "s1", subSub: "edited youtube videos"), into: db)

        let service = SearchService(
            database: db,
            vectorIndex: try VectorIndex(location: .inMemory),
            embedder: FakeEmbeddingService(unavailable: true)
        )

        let semantic = try await service.semanticSearch("videos", k: 10)
        XCTAssertEqual(semantic, [], "an unavailable model yields no semantic hits, not an error")

        let results = try await service.search("videos", limit: 10)
        XCTAssertEqual(results.map(\.id), ["s1"], "keyword arm still returns results")
    }

    func testIndexThenSemanticSearchRoundTrip() async throws {
        let db = try DatabaseService(inMemory: true)
        let s1 = try insert(makeSegment(id: "s1", subSub: "deep work on the planner"), into: db)

        let embedder = FakeEmbeddingService(vectors: [
            SearchRanker.embeddableText(for: s1): oneHot(7),
            "planner": oneHot(7),
        ])
        let index = try VectorIndex(location: .inMemory)
        let service = SearchService(database: db, vectorIndex: index, embedder: embedder)

        try await service.index(s1)
        let semantic = try await service.semanticSearch("planner", k: 5)
        XCTAssertEqual(semantic, ["s1"])
    }
}
