import Foundation
import GRDB

/// Daily job that enforces the raw-capture retention window: deletes
/// `activity_observations` older than `SettingsStore.rawRetentionDays` (default
/// 14). Judged `activity_segments` and summaries are durable and untouched —
/// only the verbatim raw text is pruned, which is the core privacy lever.
///
/// The boundary computation is a pure static function so the "keep within /
/// delete outside" logic is unit-testable without a database or a clock.
final class RetentionPruner {
    private let database: DatabaseService
    private let settings: SettingsStore
    private let interval: TimeInterval
    private let now: () -> Date
    private var timer: Timer?

    /// 24h cadence.
    init(
        database: DatabaseService,
        settings: SettingsStore,
        interval: TimeInterval = 24 * 60 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.settings = settings
        self.interval = interval
        self.now = now
    }

    // MARK: - Pure boundary logic

    /// The cutoff instant: observations with `captured_at` strictly before this
    /// are deleted; everything at or after it is kept. A non-positive retention
    /// is clamped to 0 (cutoff == now), never negative (which would keep future
    /// rows forever / delete nothing unexpectedly).
    static func cutoff(now: Date, retentionDays: Int) -> Date {
        let days = max(0, retentionDays)
        return now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
    }

    /// Pure predicate mirroring the SQL delete: true when a row captured at
    /// `capturedAt` should be removed under the given cutoff.
    static func shouldDelete(capturedAt: Date, cutoff: Date) -> Bool {
        capturedAt < cutoff
    }

    // MARK: - Execution

    /// Runs one prune pass and returns the number of rows deleted.
    @discardableResult
    func pruneNow() throws -> Int {
        let cutoff = Self.cutoff(now: now(), retentionDays: settings.rawRetentionDays)
        return try database.dbQueue.write { db in
            try ActivityObservation
                .filter(Column("captured_at") < cutoff)
                .deleteAll(db)
        }
    }

    /// Starts the daily timer (and prunes once immediately). Idempotent.
    func start() {
        guard timer == nil else { return }
        try? pruneNow()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            try? self?.pruneNow()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
