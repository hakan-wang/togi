import Foundation
import GRDB

/// Hybrid local search over the data bank: keyword (FTS5) + semantic (VectorIndex).
/// Used by the coach (retrieval) and the bank browse. Returns segment ids, best first.
final class SearchService {
    private let database: DatabaseService
    private let index: VectorIndex
    private let embedder: EmbeddingService

    init(database: DatabaseService, index: VectorIndex, embedder: EmbeddingService) {
        self.database = database
        self.index = index
        self.embedder = embedder
    }

    /// Index a segment's description for both keyword + semantic search.
    func indexSegment(id: String, description: String) {
        try? database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM segment_fts WHERE segment_id = ?", arguments: [id])
            try db.execute(
                sql: "INSERT INTO segment_fts (segment_id, description) VALUES (?, ?)",
                arguments: [id, description]
            )
        }
        if let vector = embedder.embed(description) {
            index.upsert(segmentId: id, vector: vector)
        }
    }

    func search(_ query: String, limit: Int = 20) -> [String] {
        var ranked: [String] = []
        var seen = Set<String>()

        // Semantic first (handles fuzzy intent), then keyword fills exact-term gaps.
        if let qv = embedder.embed(query) {
            for hit in index.search(qv, limit: limit) where !seen.contains(hit.segmentId) {
                ranked.append(hit.segmentId); seen.insert(hit.segmentId)
            }
        }
        for id in keywordMatch(query, limit: limit) where !seen.contains(id) {
            ranked.append(id); seen.insert(id)
        }
        return Array(ranked.prefix(limit))
    }

    private func keywordMatch(_ query: String, limit: Int) -> [String] {
        let tokens = query.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        let matchExpr = tokens.map { "\"\($0)\"" }.joined(separator: " OR ")
        return (try? database.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT segment_id FROM segment_fts WHERE segment_fts MATCH ? LIMIT ?",
                arguments: [matchExpr, limit]
            )
        }) ?? []
    }
}
