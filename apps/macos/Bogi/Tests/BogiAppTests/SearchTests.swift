import XCTest
@testable import BogiApp

/// Deterministic embedder for index/search tests (Apple NLEmbedding availability varies).
private final class FakeEmbedding: EmbeddingService {
    let table: [String: [Float]]
    let dim: Int
    init(table: [String: [Float]], dim: Int) { self.table = table; self.dim = dim }
    var dimension: Int { dim }
    func embed(_ text: String) -> [Float]? { table[text] }
}

final class SearchTests: XCTestCase {

    func testVectorIndexReturnsNearestFirst() throws {
        let db = try DatabaseService(inMemory: true)
        let index = VectorIndex(database: db)
        index.upsert(segmentId: "x", vector: [1, 0, 0])
        index.upsert(segmentId: "y", vector: [0, 1, 0])
        index.upsert(segmentId: "z", vector: [0, 0, 1])

        let results = index.search([0.9, 0.1, 0], limit: 2)
        XCTAssertEqual(results.first?.segmentId, "x")
        XCTAssertEqual(results.count, 2)
    }

    func testFTSKeywordMatch() throws {
        let db = try DatabaseService(inMemory: true)
        let embedder = FakeEmbedding(table: [:], dim: 3) // force keyword-only path
        let search = SearchService(database: db, index: VectorIndex(database: db), embedder: embedder)

        search.indexSegment(id: "a", description: "scrolling LinkedIn feed")
        search.indexSegment(id: "b", description: "editing video timeline in Final Cut")

        XCTAssertEqual(search.search("linkedin"), ["a"])
        XCTAssertEqual(search.search("video"), ["b"])
    }

    func testIndexesComposedCategoryPath() throws {
        let db = try DatabaseService(inMemory: true)
        let embedder = FakeEmbedding(table: [:], dim: 3) // keyword-only path
        let search = SearchService(database: db, index: VectorIndex(database: db), embedder: embedder)

        // Build the description the record path composes from a segment's category fields.
        let desc = ["Distraction", "Social", "Scrolling X feed"]
            .compactMap { $0 }.joined(separator: " — ")
        search.indexSegment(id: "seg1", description: desc)

        XCTAssertEqual(search.search("scrolling"), ["seg1"])
        XCTAssertEqual(search.search("distraction"), ["seg1"])
    }

    func testHybridPrefersSemanticThenKeyword() throws {
        let db = try DatabaseService(inMemory: true)
        let vectors: [String: [Float]] = [
            "compensation talk": [1, 0, 0],
            "salary": [0.95, 0.05, 0],     // query — semantically near "compensation"
            "lunch break": [0, 1, 0]
        ]
        let embedder = FakeEmbedding(table: vectors, dim: 3)
        let index = VectorIndex(database: db)
        let search = SearchService(database: db, index: index, embedder: embedder)

        // Index two segments; only descriptions present in the fake table get vectors.
        search.indexSegment(id: "pay", description: "compensation talk")
        search.indexSegment(id: "food", description: "lunch break")

        let results = search.search("salary")
        XCTAssertEqual(results.first, "pay") // semantic nearest even though no word overlap
    }
}
