import Foundation
import GRDB

/// Hybrid search over the durable activity-segment bank, combining:
///   1. **FTS5 keyword** match over `segment_fts` (created by the migrator;
///      columns `sub_sub`, `category`, `sub_category`), and
///   2. **semantic KNN** over `segment_vec` via `VectorIndex` + an
///      `EmbeddingService`.
///
/// The two ranked lists are fused with Reciprocal Rank Fusion (a pure,
/// score-free merge) and resolved back to `ActivitySegment` rows. Used by the
/// coach (Q&A retrieval) and the data-bank browse views.
public actor SearchService {
    private let database: DatabaseService
    private let vectorIndex: VectorIndex
    private let embedder: EmbeddingService

    public init(database: DatabaseService, vectorIndex: VectorIndex, embedder: EmbeddingService) {
        self.database = database
        self.vectorIndex = vectorIndex
        self.embedder = embedder
    }

    /// Embeds a segment's text and stores it in the vector index. The judge
    /// calls this after writing a segment so it becomes semantically
    /// searchable. Keyword search is populated automatically by the FTS5
    /// triggers when the segment row is inserted.
    public func index(_ segment: ActivitySegment) async throws {
        let text = SearchRanker.embeddableText(for: segment)
        guard !text.isEmpty else { return }
        let vector = try await embedder.embed(text)
        try await vectorIndex.upsert(segmentId: segment.id, embedding: vector)
    }

    /// Hybrid search. Returns segments ordered by fused relevance, capped at
    /// `limit`. Either retrieval arm degrading to empty (no keyword hits, or the
    /// embedding model being unavailable) still yields results from the other.
    public func search(_ query: String, limit: Int = 20) async throws -> [ActivitySegment] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }

        let keywordIds = try keywordSearch(trimmed, limit: limit)
        let semanticIds = try await semanticSearch(trimmed, k: limit)
        let fused = SearchRanker.reciprocalRankFusion([keywordIds, semanticIds])
        return try fetchSegments(ids: Array(fused.prefix(limit)))
    }

    // MARK: - Retrieval arms (internal for testing)

    /// FTS5 keyword arm. Returns segment ids ordered by bm25 (best first).
    func keywordSearch(_ query: String, limit: Int) throws -> [String] {
        let match = SearchRanker.ftsQuery(for: query)
        guard !match.isEmpty else { return [] }
        return try database.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT s.id
                    FROM segment_fts
                    JOIN activity_segments s ON s.rowid = segment_fts.rowid
                    WHERE segment_fts MATCH ?
                    ORDER BY bm25(segment_fts)
                    LIMIT ?
                    """,
                arguments: [match, limit]
            )
        }
    }

    /// Semantic arm. Embeds the query and runs KNN; returns segment ids ordered
    /// by distance (closest first). If the embedding model is unavailable the
    /// arm yields nothing rather than failing the whole search.
    func semanticSearch(_ query: String, k: Int) async throws -> [String] {
        let vector: [Float]
        do {
            vector = try await embedder.embed(query)
        } catch EmbeddingError.modelUnavailable, EmbeddingError.emptyInput {
            return []
        }
        let neighbors = try await vectorIndex.knn(query: vector, k: k)
        return neighbors.map(\.segmentId)
    }

    /// Fetches segments by id and returns them in the same order as `ids`
    /// (GRDB's batch fetch does not preserve key order).
    func fetchSegments(ids: [String]) throws -> [ActivitySegment] {
        guard !ids.isEmpty else { return [] }
        let byId: [String: ActivitySegment] = try database.dbQueue.read { db in
            try ActivitySegment.fetchAll(db, keys: ids)
        }
        .reduce(into: [:]) { $0[$1.id] = $1 }
        return ids.compactMap { byId[$0] }
    }
}

// MARK: - Pure ranking / query helpers (framework-light, unit-testable)

/// Pure helpers powering hybrid search: rank fusion, FTS query sanitization, and
/// the text used to embed a segment. No I/O, fully deterministic.
public enum SearchRanker {
    /// Reciprocal Rank Fusion. Each input list is assumed ordered best-first.
    /// An id's fused score is `Σ 1 / (k + rank)` across the lists it appears in
    /// (rank is 1-based). Returns de-duplicated ids ordered by descending score;
    /// ties break by earliest appearance for a stable, deterministic order.
    ///
    /// `k` (default 60, the value from the original RRF paper) damps the
    /// influence of any single list's top ranks.
    public static func reciprocalRankFusion(_ rankedLists: [[String]], k: Double = 60) -> [String] {
        var scores: [String: Double] = [:]
        var firstSeen: [String: Int] = [:]
        var order = 0
        for list in rankedLists {
            for (index, id) in list.enumerated() {
                scores[id, default: 0] += 1.0 / (k + Double(index + 1))
                if firstSeen[id] == nil {
                    firstSeen[id] = order
                    order += 1
                }
            }
        }
        return scores.keys.sorted { lhs, rhs in
            let lScore = scores[lhs] ?? 0
            let rScore = scores[rhs] ?? 0
            if lScore != rScore { return lScore > rScore }
            return (firstSeen[lhs] ?? 0) < (firstSeen[rhs] ?? 0)
        }
    }

    /// Builds a safe FTS5 `MATCH` expression from free-form user text: lowercase,
    /// split on non-alphanumerics, drop empties, double-quote each term (so FTS5
    /// treats it as a literal, never an operator) and OR them together. Returns
    /// `""` when there is nothing searchable.
    public static func ftsQuery(for raw: String) -> String {
        let terms = raw
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return "" }
        return terms.map { "\"\($0)\"" }.joined(separator: " OR ")
    }

    /// The text Bogi embeds for a segment: its concrete description plus its
    /// taxonomy, most-specific first. Mirrors the FTS5 columns.
    public static func embeddableText(for segment: ActivitySegment) -> String {
        [segment.subSub, segment.subCategory, segment.category]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
