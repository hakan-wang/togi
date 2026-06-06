import AppKit
import SwiftUI

/// App-wide singletons: the local DB, capture loop, AI/auth, planner, and the data-bank
/// services that the dashboard + coach read from.
final class AppState: ObservableObject {
    let database: DatabaseService
    let settings: SettingsStore
    let capture: CaptureController

    let auth: SupabaseAuth
    let accountGate: AccountGate
    let inference: InferenceClient

    let observations: ObservationStore
    let segments: SegmentStore
    let plannedBlocks: PlannedBlockRepository
    let planner: PlannerService
    let eventKit: EventKitService
    let googleCalendar: GoogleCalendarService
    let search: SearchService
    let goals: GoalsService
    let northStar: NorthStarService
    let insights: InsightsService
    let sidecar: SidecarClient
    private let sidecarTransport: ProcessSidecarTransport
    let coach: CoachService

    @Published var capturePaused: Bool {
        didSet {
            capture.isPaused = capturePaused
            settings.setBool("paused", capturePaused)
        }
    }

    /// User preference for whether the floating mascot is on screen. Persisted so it
    /// survives relaunch; the panel itself lives in AppDelegate, so changes route out
    /// through `onMascotVisibilityChanged`.
    @Published var mascotVisible: Bool {
        didSet {
            settings.setBool("mascot_visible", mascotVisible)
            onMascotVisibilityChanged?(mascotVisible)
        }
    }

    /// Wired by the AppDelegate after launch (menu-bar actions call these).
    var openDashboard: (() -> Void)?
    var runJudgeNow: (() -> Void)?
    /// Wired by the AppDelegate to show/hide the mascot panel when the preference flips.
    var onMascotVisibilityChanged: ((Bool) -> Void)?

    /// Set by the AppDelegate after launch; drives the Calendars settings UI.
    @Published var calendarSync: CalendarSyncCoordinator?

    init(database: DatabaseService, databasePath: String) {
        self.database = database
        let settings = SettingsStore(database: database)
        self.settings = settings

        let excludes = CaptureExcludes.makeDefault(
            userApps: settings.stringArray("excluded_apps"),
            userDomains: settings.stringArray("excluded_domains")
        )
        self.capture = CaptureController(
            provider: AccessibilityCaptureService(),
            store: ObservationStore(database: database),
            excludes: excludes,
            pruner: RetentionPruner(database: database),
            settings: settings
        )

        let auth = SupabaseAuth()
        self.auth = auth
        self.accountGate = AccountGate(auth: auth)
        self.inference = BackendInferenceClient(
            baseURL: BackendConfig.baseURL,
            tokenProvider: { await auth.currentAccessToken() }
        )

        let plannedBlocks = PlannedBlockRepository(database: database)
        self.observations = ObservationStore(database: database)
        self.segments = SegmentStore(database: database)
        self.plannedBlocks = plannedBlocks
        self.eventKit = EventKitService()
        self.googleCalendar = GoogleCalendarService()
        self.search = SearchService(
            database: database,
            index: VectorIndex(database: database),
            embedder: AppleSentenceEmbedding()
        )
        let goals = GoalsService(database: database)
        let insights = InsightsService(database: database)
        let northStarSync = NorthStarSync(tokenProvider: { await auth.currentAccessToken() })
        let northStar = NorthStarService(database: database, sync: northStarSync)
        self.goals = goals
        self.insights = insights
        self.northStar = northStar

        // On-device agent sidecar (bundled Node + LangChain.js). Coach, Planner, and the
        // nudge path all route through it; raw data never leaves the device.
        let resources = Bundle.main.resourceURL!.appendingPathComponent("sidecar")
        let env: [String: String] = [
            "BOGI_BACKEND_URL": BackendConfig.baseURL.absoluteString,
            "BOGI_AUTH_TOKEN": "",   // filled per-request via the proxy; placeholder for launch
            "BOGI_DB_PATH": databasePath,
            // better-sqlite3 ships next to main.cjs, so require() resolves it from the sidecar dir.
            "NODE_PATH": resources.path,
        ]
        let transport = ProcessSidecarTransport(
            nodeURL: resources.appendingPathComponent("node"),
            scriptURL: resources.appendingPathComponent("main.cjs"),
            environment: env)
        self.sidecarTransport = transport
        let sidecar = SidecarClient(transport: transport)
        self.sidecar = sidecar

        self.planner = PlannerService(repository: plannedBlocks, sidecar: sidecar)
        self.coach = CoachService(backend: sidecar, threadId: "coach")

        let paused = settings.bool("paused", default: false)
        self.capturePaused = paused
        capture.isPaused = paused

        self.mascotVisible = settings.bool("mascot_visible", default: true)
    }

    /// Inject a freshly-fetched auth token into the sidecar's environment, then launch it.
    /// Called once at startup after the access token is available.
    func startSidecar() async {
        let token = await auth.currentAccessToken() ?? ""
        sidecarTransport.environment["BOGI_AUTH_TOKEN"] = token
        // WebSocket streaming endpoint (Bedrock ConverseStream). The sidecar streams model
        // turns over this and emits token-by-token frames; on any WS failure (e.g. an expired
        // token) it transparently degrades to the HTTP /v1/infer path. An env override wins so
        // tests/dev can point elsewhere.
        let wsURL = ProcessInfo.processInfo.environment["BOGI_WS_URL"]
            ?? "wss://spz67o2b6l.execute-api.eu-west-1.amazonaws.com/prod"
        sidecarTransport.environment["BOGI_WS_URL"] = wsURL
        do { try sidecar.start() } catch {
            NSLog("Bogi: failed to start sidecar: \(error)")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    private var mascot: MascotPanel?
    private let presenter = NudgePresenter()
    private var coordinator: JudgeCoordinator?
    private var companion: CompanionPanel?
    private var onboardingWindow: OnboardingWindow?

    override init() {
        let db: DatabaseService
        let path = DatabaseService.defaultPath()
        var dbPath = path
        do {
            db = try DatabaseService(path: path)
        } catch {
            NSLog("Bogi: failed to open database: \(error). Falling back to in-memory.")
            db = try! DatabaseService(inMemory: true)
            dbPath = ":memory:"
        }
        appState = AppState(database: db, databasePath: dbPath)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if appState.settings.bool("onboarding_completed", default: false) {
            startNormalRuntime()
        } else {
            presentOnboarding()
        }

        // Best-effort: pull the North Star from the account so it follows the user across devices.
        Task { await appState.northStar.refresh() }
    }

    /// First-run setup. Shown once; on completion it hands off to the normal runtime. The capture
    /// loop, mascot, and judge are intentionally NOT started until setup finishes — the Accessibility
    /// primer (step 5) owns the permission ask, and the mascot shouldn't float over onboarding.
    private func presentOnboarding() {
        let coordinator = OnboardingCoordinator(
            northStar: appState.northStar,
            capture: appState.capture,
            planner: appState.planner,
            googleCalendar: appState.googleCalendar,
            settings: appState.settings,
            auth: appState.auth,
            notifications: NotificationAuthorizer()
        ) { [weak self] in
            self?.onboardingWindow?.orderOut(nil)
            self?.onboardingWindow = nil
            self?.startNormalRuntime()
        }
        let window = OnboardingWindow(coordinator: coordinator)
        coordinator.hostWindow = window
        onboardingWindow = window
        window.present()
    }

    /// The normal menu-bar runtime: capture loop, floating mascot, and the 5-minute judge.
    private func startNormalRuntime() {
        if appState.capture.permissionState != .granted {
            appState.capture.requestPermission()
        }
        appState.capture.start()

        let mascot = MascotPanel()
        mascot.onActivate = { [weak self] in self?.toggleCompanion() }
        if appState.mascotVisible { mascot.show() }
        self.mascot = mascot
        appState.onMascotVisibilityChanged = { [weak self] visible in
            if visible { self?.mascot?.show() } else { self?.mascot?.hide() }
        }

        // Wire the agent's action tools to app-only side effects: calendar writes, nudges,
        // and persisting the segments the agent produced from recent activity.
        let planner = appState.planner
        let presenter = self.presenter
        let segmentStore = appState.segments
        let search = appState.search
        let actions = SidecarActionHandlers(
            createBlock: { title, start, end in
                await MainActor.run {
                    planner.createLocalBlock(title: title, start: start, end: end, category: nil).id
                }
            },
            moveBlock: { match, start, end in
                await MainActor.run {
                    planner.moveBlock(matching: match, start: start, end: end)?.id
                }
            },
            postNudge: { [weak self] severity, message in
                await MainActor.run {
                    guard let self else { return }
                    let decision = presenter.present(message: message, now: Date())
                    self.applyNudge(decision, onTask: false)
                }
            },
            recordSegments: { segs in
                await MainActor.run {
                    segs.forEach {
                        segmentStore.insert($0)
                        let desc = [$0.category, $0.subCategory, $0.subSub].compactMap { $0 }.joined(separator: " — ")
                        if !desc.isEmpty { search.indexSegment(id: $0.id, description: desc) }
                    }
                    return segs.count
                }
            })
        appState.sidecar.actionHandler = { name, input in await actions.handle(name, input) }

        // Supply a fresh auth token on every chat/plan/judge request. The token rotates
        // ~hourly, so baking it into the sidecar env at launch would 401 after expiry once
        // auth is enforced. This threads a current token per request instead.
        appState.sidecar.tokenProvider = { [weak self] in await self?.appState.auth.currentAccessToken() }

        // Launch the sidecar once a fresh auth token is available.
        Task { await self.appState.startSidecar() }

        let coordinator = JudgeCoordinator(
            observations: appState.observations,
            blocks: appState.plannedBlocks,
            segments: appState.segments,
            sidecar: appState.sidecar
        )
        coordinator.start()
        self.coordinator = coordinator

        appState.openDashboard = { [weak self] in self?.showCompanion() }
        appState.runJudgeNow = { [weak self] in Task { await self?.coordinator?.tick() } }

        let calendarSync = CalendarSyncCoordinator(
            google: appState.googleCalendar, planner: appState.planner, settings: appState.settings
        )
        calendarSync.start()
        appState.calendarSync = calendarSync
    }

    private func applyNudge(_ decision: NudgeDecision, onTask: Bool) {
        guard let mascot else { return }
        if decision.show {
            // Auto-reappear even when hidden, so a real nudge still reaches the user.
            mascot.show()
            mascot.apply(decision)
            if decision.playSound { NSSound.beep() }
        } else {
            mascot.update(mood: onTask ? .onTask : .offTask)
            // Settle back to hidden once the nudge has passed, honoring the preference.
            if !appState.mascotVisible { mascot.hide() }
        }
    }

    private func companionPanel() -> CompanionPanel {
        if let companion { return companion }
        let state = appState
        let panel = CompanionPanel {
            CompanionView(
                insight: { period in state.insights.insight(for: period, containing: Date()) },
                ask: { question, onToken in try await state.coach.ask(question, onToken: onToken) },
                onClose: { [weak self] in self?.companion?.orderOut(nil) }
            )
            .environmentObject(state)
        }
        companion = panel
        return panel
    }

    private func showCompanion() { companionPanel().show() }
    private func toggleCompanion() { companionPanel().toggle() }

    private static func openSettings() {
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
