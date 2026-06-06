import Foundation
import SQLiteVec

/// On-device semantic index over segment embeddings, backed by the sqlite-vec
/// `vec0` virtual table `segment_vec(embedding float[256])`.
///
/// The GRDB migrator deliberately does **not** create `segment_vec`: a `vec0`
/// virtual table requires the loadable sqlite-vec extension, which GRDB does not
/// load. `VectorIndex` therefore (1) loads the extension via
/// `SQLiteVec.initialize()` and (2) creates the table at runtime with
/// `CREATE VIRTUAL TABLE IF NOT EXISTS`.
///
/// `vec0` rows are addressed by an integer rowid, but Bogi's segments use TEXT
/// ids. A small companion table `segment_vec_ids` maps `segment_id TEXT` ⇄
/// `rowid INTEGER`, so callers only ever deal in segment ids.
///
/// **Runtime-only / macOS-only.** sqlite-vec is a native SQLite extension that
/// is only present at runtime on macOS. This file is not compiled or exercised
/// by the Linux CI used for these PRs.
///
/// This type owns its **own** `SQLiteVec.Database` connection (the sqlite-vec
/// library is designed to be driven through its own `Database`). Point it at the
/// same on-disk path as the GRDB database so `segment_vec` lives in the same
/// file (see the PR's *Integration points*), or use `.inMemory` for tests.
public actor VectorIndex {
    /// A nearest-neighbour hit: the segment id and its sqlite-vec L2 distance
    /// (smaller = closer).
    public struct Neighbor: Equatable, Sendable {
        public let segmentId: String
        public let distance: Double
        public init(segmentId: String, distance: Double) {
            self.segmentId = segmentId
            self.distance = distance
        }
    }

    private let db: Database
    private let dimension: Int
    private var didCreateSchema = false

    /// Opens (or creates) the vector store at `location`.
    ///
    /// - Parameters:
    ///   - location: `.inMemory` (default, used by tests), `.temporary`, or
    ///     `.uri(path)` pointing at the shared GRDB database file.
    ///   - dimension: embedding width; must equal what the embedder produces.
    public init(location: Database.Location = .inMemory, dimension: Int = bogiEmbeddingDimension) throws {
        // Loads the sqlite-vec extension into the process. Idempotent and must
        // run before any `vec0` table is created or queried.
        try SQLiteVec.initialize()
        self.db = try Database(location)
        self.dimension = dimension
    }

    /// Lazily creates `segment_vec` and its id-mapping table. Safe to call
    /// repeatedly thanks to `IF NOT EXISTS` and the `didCreateSchema` guard.
    private func ensureSchema() async throws {
        guard !didCreateSchema else { return }
        try await db.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS segment_vec USING vec0(embedding float[\(dimension)])"
        )
        try await db.execute(
            """
            CREATE TABLE IF NOT EXISTS segment_vec_ids(
                rowid INTEGER PRIMARY KEY AUTOINCREMENT,
                segment_id TEXT NOT NULL UNIQUE
            )
            """
        )
        didCreateSchema = true
    }

    /// Inserts or replaces the embedding for `segmentId`. Re-embedding a segment
    /// overwrites its previous vector.
    public func upsert(segmentId: String, embedding: [Float]) async throws {
        guard embedding.count == dimension else { throw EmbeddingError.embeddingFailed }
        try await ensureSchema()

        let rowid = try await rowId(for: segmentId)
        // vec0 has no UPSERT, so delete any prior vector then insert fresh.
        try await db.execute("DELETE FROM segment_vec WHERE rowid = ?", params: [rowid])
        try await db.execute(
            "INSERT INTO segment_vec(rowid, embedding) VALUES (?, ?)",
            params: [rowid, embedding]
        )
    }

    /// Returns the `k` nearest segments to `query`, closest first.
    public func knn(query: [Float], k: Int) async throws -> [Neighbor] {
        guard k > 0 else { return [] }
        guard query.count == dimension else { throw EmbeddingError.embeddingFailed }
        try await ensureSchema()

        let rows = try await db.query(
            """
            SELECT m.segment_id AS segment_id, v.distance AS distance
            FROM segment_vec v
            JOIN segment_vec_ids m ON m.rowid = v.rowid
            WHERE v.embedding MATCH ? AND k = ?
            ORDER BY v.distance
            """,
            params: [query, k]
        )
        return rows.compactMap { row in
            guard let id = row["segment_id"] as? String else { return nil }
            let distance = (row["distance"] as? Double) ?? (row["distance"] as? Float).map(Double.init) ?? 0
            return Neighbor(segmentId: id, distance: distance)
        }
    }

    /// Removes a segment's embedding (e.g. when the raw data is pruned).
    public func delete(segmentId: String) async throws {
        try await ensureSchema()
        guard let rowid = try await existingRowId(for: segmentId) else { return }
        try await db.execute("DELETE FROM segment_vec WHERE rowid = ?", params: [rowid])
        try await db.execute("DELETE FROM segment_vec_ids WHERE rowid = ?", params: [rowid])
    }

    // MARK: - id ⇄ rowid mapping

    /// Looks up the stable integer rowid for `segmentId`, creating a mapping row
    /// the first time the segment is seen.
    private func rowId(for segmentId: String) async throws -> Int {
        if let existing = try await existingRowId(for: segmentId) { return existing }
        try await db.execute(
            "INSERT INTO segment_vec_ids(segment_id) VALUES (?)",
            params: [segmentId]
        )
        return await db.lastInsertRowId
    }

    private func existingRowId(for segmentId: String) async throws -> Int? {
        let rows = try await db.query(
            "SELECT rowid FROM segment_vec_ids WHERE segment_id = ?",
            params: [segmentId]
        )
        guard let value = rows.first?["rowid"] else { return nil }
        if let i = value as? Int { return i }
        if let i64 = value as? Int64 { return Int(i64) }
        return nil
    }
}
