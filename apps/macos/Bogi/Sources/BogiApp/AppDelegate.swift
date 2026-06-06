import AppKit
import Combine
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

    /// Whether Togi launches automatically at login. Backed by the system Login Items
    /// list (via `LoginItemService`); persisted only as a record of the user's intent.
    @Published var launchAtLogin: Bool {
        didSet {
            settings.setBool("launch_at_login", launchAtLogin)
            LoginItemService.setEnabled(launchAtLogin)
        }
    }

    /// Wired by the AppDelegate after launch (menu-bar actions call these).
    var openDashboard: (() -> Void)?
    var runJudgeNow: (() -> Void)?
    /// Wired by the AppDelegate to show/hide the mascot panel when the preference flips.
    var onMascotVisibilityChanged: ((Bool) -> Void)?
    var startCalm: (() -> Void)?
    var startCalmOffer: (() -> Void)?
    /// Demo hook: set Togi's wellbeing 0…100 to preview the thrive/wilt states live.
    var setVitalityDemo: ((Double) -> Void)?

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
        self.goals = goals
        self.insights = insights

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
        // Reflect the live Login Items state so the toggle matches reality even if the
        // user changed it in System Settings. First-run opt-in happens in the delegate.
        self.launchAtLogin = LoginItemService.isEnabled
    }

    /// Inject a freshly-fetched auth token into the sidecar's environment, then launch it.
    /// Called once at startup after the access token is available.
    func startSidecar() async {
        let token = await auth.currentAccessToken() ?? ""
        sidecarTransport.environment["BOGI_AUTH_TOKEN"] = token
        // Streaming is DISABLED for this release: the WS inference endpoint currently 401s, so
        // we run HTTP-only (the sidecar streams only when BOGI_WS_URL is non-empty; otherwise it
        // uses the non-streaming HTTP /v1/infer path). A non-empty BOGI_WS_URL env override still
        // lets dev/test opt back into streaming once the endpoint auth is fixed.
        if let wsURL = ProcessInfo.processInfo.environment["BOGI_WS_URL"], !wsURL.isEmpty {
            sidecarTransport.environment["BOGI_WS_URL"] = wsURL
        }
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
    private var calm: CalmPanel?
    private var calmScheduler: CalmScheduler?
    private var gateWindow: NSWindow?
    private lazy var gate = GateController(auth: appState.auth, gate: appState.accountGate)
    private var gateObservation: AnyCancellable?
    private var mainExperienceStarted = false

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

        // Demo hook: launch straight into the calm overlay for screenshots, skipping the
        // capture loop and coordinator. BOGI_SHOW_CALM = 1|breathe|offer|intent.
        if let mode = ProcessInfo.processInfo.environment["BOGI_SHOW_CALM"] {
            switch mode {
            case "offer":  showCalm(.offer)
            case "intent": showCalm(.intent(app: "tiktok"))
            default:       showCalm(.breathe)
            }
            return
        }

        // Demo hook: show the mascot with the companion chat already open, for screenshots.
        // Skips the capture loop and coordinator. Set BOGI_SHOW_COMPANION=1.
        if ProcessInfo.processInfo.environment["BOGI_SHOW_COMPANION"] == "1" {
            let mascot = MascotPanel()
            mascot.onActivate = { [weak self] in self?.toggleCompanion() }
            mascot.show()
            self.mascot = mascot
            showCompanion()
            return
        }

        // Gate the whole app on a signed-in, subscribed user (strict online check).
        gateObservation = gate.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.applyGateState(state) }
        Task { await gate.refresh() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard mainExperienceStarted || gateWindow != nil else { return }
        Task { await gate.refresh() }
    }

    private func applyGateState(_ state: GateState) {
        switch state {
        case .unlocked:
            gateWindow?.orderOut(nil)
            gateWindow = nil
            startMainExperienceIfNeeded()
        case .checking:
            // Initial launch shows a "checking" window; once the app is running, a transient
            // re-check (e.g. on activation) must not flash a window over the live UI.
            if !mainExperienceStarted { showGateWindow(for: .checking) }
        case .needsLogin, .needsSubscription, .blocked:
            showGateWindow(for: state)
        }
    }

    private func showGateWindow(for state: GateState) {
        let view = GateView(
            state: state,
            signIn: { [weak self] email, pw in
                guard let self else { return }
                try await self.gate.signIn(email: email, password: pw)
            },
            openWebsite: { NSWorkspace.shared.open(WebsiteConfig.pricingURL) },
            onSubscribe: { NSWorkspace.shared.open(WebsiteConfig.pricingURL) },
            onRecheck: { [weak self] in Task { await self?.gate.refresh() } },
            onSignOut: { [weak self] in self?.gate.signOut() }
        )
        if let win = gateWindow {
            win.contentViewController = NSHostingController(rootView: view)
        } else {
            let win = NSWindow(contentViewController: NSHostingController(rootView: view))
            win.styleMask = [.titled]
            win.title = "Togi"
            win.isReleasedWhenClosed = false
            win.center()
            gateWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        gateWindow?.makeKeyAndOrderFront(nil)
    }

    /// Everything that used to run unconditionally in applicationDidFinishLaunching — now only
    /// after the gate unlocks, and only once.
    private func startMainExperienceIfNeeded() {
        guard !mainExperienceStarted else { return }
        mainExperienceStarted = true
        startMainExperience()
    }

    private func startMainExperience() {
        // First launch: opt into launch-at-login so Togi reappears every login with no setup.
        // Gated behind unlock so we only auto-launch for real (subscribed) users, not someone
        // who opened the app once and hit the paywall. Only on the very first unlocked run
        // (no stored preference) — respect later changes.
        if appState.settings.string("launch_at_login") == nil {
            appState.launchAtLogin = true
        }

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

        appState.startCalm = { [weak self] in self?.showCalm() }
        appState.startCalmOffer = { [weak self] in self?.showCalmOffer() }
        appState.setVitalityDemo = { [weak self] value in self?.mascot?.viewModel.setVitality(value) }

        // Proactive, benign nudge: after a long unbroken stretch, Togi offers a breath.
        // Time-on-task only — no emotion guessing. BOGI_CALM_NUDGE_SECS overrides for demos.
        let nudgeSecs = Double(ProcessInfo.processInfo.environment["BOGI_CALM_NUDGE_SECS"] ?? "") ?? (50 * 60)
        let scheduler = CalmScheduler(
            interval: nudgeSecs,
            isPaused: { [weak self] in self?.appState.capturePaused ?? true },
            onNudge: { [weak self] in self?.showCalmOffer() }
        )
        scheduler.start()
        calmScheduler = scheduler
    }

    private func applyNudge(_ decision: NudgeDecision, onTask: Bool) {
        guard let mascot else { return }
        // Wellbeing rides the real loop: each read nudges Togi toward thriving (on-task)
        // or wilting (off-task). The body's look follows in MascotView.
        mascot.viewModel.nudgeVitality(onTask: onTask)
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
        // Demo hook: BOGI_DEMO_CHAT=1 opens with a sample conversation so the grown,
        // scrolling card can be screenshotted. Empty otherwise.
        let seed: [(role: String, text: String)] = ProcessInfo.processInfo.environment["BOGI_DEMO_CHAT"] == "1" ? [
            ("user", "how am i doing today?"),
            ("coach", "not great. 2h 41m logged and only 38% of it was on task. social ate 47 minutes you never planned for."),
            ("user", "what should i do about it?"),
            ("coach", "close the social tabs, set a 25-minute timer, and finish the deck you opened at 9am and walked away from. tell me when it's done."),
        ] : []
        let panel = CompanionPanel { maxContentHeight, reportHeight in
            CompanionView(
                insight: { period in state.insights.insight(for: period, containing: Date()) },
                ask: { question, onToken in try await state.coach.ask(question, onToken: onToken) },
                suggest: {
                    CoachService.buildSuggestions(
                        insight: state.insights.insight(for: .day, containing: Date()),
                        goals: state.goals.all()
                    )
                },
                maxContentHeight: maxContentHeight,
                onHeightChange: reportHeight,
                onSettings: { AppDelegate.openSettings() },
                onClose: { [weak self] in self?.companion?.orderOut(nil) },
                seedMessages: seed
            )
            .environmentObject(state)
        }
        companion = panel
        return panel
    }

    private func showCompanion() { companionPanel().show() }
    private func toggleCompanion() { companionPanel().toggle() }

    private func showCalm(_ start: CalmStart = .breathe) {
        calm?.orderOut(nil)
        let panel = CalmPanel {
            CalmView(
                start: start,
                onOpen: { [weak self] app in self?.openGatedApp(app) },
                onDone: { [weak self] in self?.calm?.hide() }
            )
        }
        calm = panel
        calmScheduler?.noteBreath()
        panel.show()
    }

    private func showCalmOffer() { showCalm(.offer) }

    private func openGatedApp(_ app: String) {
        calm?.hide()
        if app.lowercased().contains("tiktok"), let url = URL(string: "https://www.tiktok.com") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func openSettings() {
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
