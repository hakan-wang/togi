import Foundation
import GRDB

/// Local semantic index. Brute-force exact cosine KNN over BLOB-stored vectors — the same
/// exact-search behavior as sqlite-vec, ample at personal-bank scale, with no extension to
/// load. `segment_embeddings` is the backing table (added in migration v2_search).
final class VectorIndex {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    func upsert(segmentId: String, vector: [Float]) {
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        try? database.dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO segment_embeddings (segment_id, vector, dim) VALUES (?, ?, ?)",
                arguments: [segmentId, data, vector.count]
            )
        }
    }

    /// Returns the `limit` most cosine-similar segment ids, highest first.
    func search(_ query: [Float], limit: Int) -> [(segmentId: String, score: Float)] {
        guard !query.isEmpty else { return [] }
        let qNorm = norm(query)
        guard qNorm > 0 else { return [] }

        let rows: [(String, [Float])] = (try? database.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT segment_id, vector FROM segment_embeddings").map { row in
                let id: String = row["segment_id"]
                let data: Data = row["vector"]
                return (id, Self.floats(from: data))
            }
        }) ?? []

        let scored = rows.compactMap { (id, vec) -> (String, Float)? in
            guard vec.count == query.count else { return nil }
            let n = norm(vec)
            guard n > 0 else { return nil }
            return (id, dot(query, vec) / (qNorm * n))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { (segmentId: $0.0, score: $0.1) }
    }

    // MARK: - math / encoding

    private func dot(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<a.count { s += a[i] * b[i] }
        return s
    }

    private func norm(_ a: [Float]) -> Float {
        var s: Float = 0
        for v in a { s += v * v }
        return s.squareRoot()
    }

    private static func floats(from data: Data) -> [Float] {
        data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
    }
}
