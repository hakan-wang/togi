import Foundation
import Combine

/// A no-op token provider used before sign-in (or when Supabase is not
/// configured). Returning `nil` makes `InferenceClientLive` throw
/// `.notAuthenticated`, which the gate surfaces as "please sign in".
private final class NullTokenProvider: AccessTokenProviding {
    func accessToken() async -> String? { nil }
}

/// Shared, app-wide dependency container. Built once at launch (see `AppDelegate`)
/// and injected into SwiftUI scenes.
///
/// This is the integration seam: each feature module ships its services with
/// narrow initializers and seam protocols (`InferenceClient`, `SegmentEmbedder`,
/// `NudgeSink`, `CalendarSource`, `SegmentRetrieving`), and this container is
/// where the concrete wiring happens. The graph is built so the app always
/// launches: optional pieces (Supabase auth, the sqlite-vec index) degrade
/// gracefully to nil rather than aborting startup.
@MainActor
final class AppEnvironment: ObservableObject {
    // Foundation
    let database: DatabaseService
    let settings: SettingsStore
    /// On-disk database path, or `nil` for the in-memory fallback. Used to point
    /// the sqlite-vec index at the same file.
    let databasePath: String?

    // Backend / auth
    let backendConfig: BackendConfig
    /// `nil` when Supabase is not configured (no URL/anon key); the app still
    /// launches and shows the login/paywall gate as "not configured".
    let auth: SupabaseAuth?
    let inferenceClient: InferenceClient
    /// `nil` when `auth` is nil (nothing to gate against).
    let accountGate: AccountGate?

    // Capture (Phase 1)
    let observationStore: ObservationStore
    let capture: AccessibilityCaptureService
    let retentionPruner: RetentionPruner

    // Embeddings + search (Phase 2)
    let embeddingService: EmbeddingService
    /// `nil` if the sqlite-vec extension/store could not be opened; the judge
    /// then skips embedding and the coach falls back to FTS-only retrieval.
    let vectorIndex: VectorIndex?
    private let segmentEmbedder: SegmentEmbedderAdapter?

    // Planner + calendars (Phase 4)
    let planner: PlannerService

    // Judge (Phase 5)
    let judge: JudgeService

    // Mascot + nudges (Phase 6)
    let mascot: MascotController
    let nudgePresenter: NudgePresenter

    // Coach + data bank (Phase 7)
    let goals: GoalsService
    let coach: CoachService

    init(database: DatabaseService, databasePath: String?) {
        self.database = database
        self.databasePath = databasePath
        let settings = SettingsStore(database: database)
        self.settings = settings

        // --- Backend + auth -------------------------------------------------
        let backendConfig = BackendConfig.resolved()
        self.backendConfig = backendConfig
        let auth = SupabaseConfig.resolved().map { SupabaseAuth(config: $0) }
        self.auth = auth
        let tokenProvider: AccessTokenProviding = auth ?? NullTokenProvider()
        self.inferenceClient = InferenceClientLive(config: backendConfig, tokenProvider: tokenProvider)
        self.accountGate = auth.map {
            AccountGate(
                auth: $0,
                statusChecker: AccountStatusClient(config: backendConfig),
                database: database
            )
        }

        // --- Capture --------------------------------------------------------
        let observationStore = ObservationStore(database: database)
        self.observationStore = observationStore
        self.capture = AccessibilityCaptureService(store: observationStore, settings: settings)
        self.retentionPruner = RetentionPruner(database: database, settings: settings)

        // --- Embeddings + vector index -------------------------------------
        let embeddingService = EmbeddingServiceFactory.make(settings: settings)
        self.embeddingService = embeddingService
        // Point the sqlite-vec store at the same on-disk file as GRDB so
        // `segment_vec` lives alongside the rest of the schema. In-memory builds
        // skip the persistent index (tests construct their own).
        let vectorIndex = databasePath.flatMap { try? VectorIndex(location: .uri($0)) }
        self.vectorIndex = vectorIndex
        self.segmentEmbedder = vectorIndex.map { SegmentEmbedderAdapter(embedding: embeddingService, index: $0) }

        // --- Planner --------------------------------------------------------
        self.planner = PlannerService(database: database)

        // --- Judge (heartbeat) ----------------------------------------------
        let nudgeOutcomes = DatabaseNudgeOutcomeStore(database: database)
        let mascot = MascotController()
        self.mascot = mascot
        let nudgePresenter = NudgePresenter(
            bubble: mascot,
            outcomes: nudgeOutcomes,
            dndWindowsProvider: { [] },
            globalDNDProvider: { [weak settings] in settings?.bool(.dnd) ?? false }
        )
        self.nudgePresenter = nudgePresenter
        mascot.presenter = nudgePresenter

        self.judge = JudgeService(
            database: database,
            inference: inferenceClient,
            settings: settings,
            embedder: segmentEmbedder,
            nudgeSink: nudgePresenter
        )

        // --- Coach + goals --------------------------------------------------
        let goals = GoalsService(database: database)
        self.goals = goals
        self.coach = CoachService(
            inference: inferenceClient,
            database: database,
            goals: goals,
            retriever: FTSSegmentRetriever(database: database)
        )
    }

    /// Production environment backed by an on-disk SQLite database in
    /// Application Support. Falls back to an in-memory database if the support
    /// directory cannot be created (the app still launches; capture is degraded).
    static func live() -> AppEnvironment {
        do {
            let url = try AppPaths.databaseURL()
            let database = try DatabaseService(path: url.path)
            return AppEnvironment(database: database, databasePath: url.path)
        } catch {
            NSLog("Bogi: falling back to in-memory database: \(error)")
            // Force-try is acceptable here: an in-memory DB creation failing
            // would indicate GRDB itself is broken, which is unrecoverable.
            let database = try! DatabaseService(inMemory: true)
            return AppEnvironment(database: database, databasePath: nil)
        }
    }
}

enum AppPaths {
    static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Bogi", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func databaseURL() throws -> URL {
        try supportDirectory().appendingPathComponent("bogi.sqlite")
    }
}
