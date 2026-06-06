import AppKit
import SwiftUI
import Combine

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
    /// Routes voice-scheduled events to Google Calendar (when connected) or Apple Calendar.
    let calendar: CalendarRouter
    let search: SearchService
    let goals: GoalsService
    let insights: InsightsService
    let coach: CoachService
    let judge: JudgeService

    @Published var capturePaused: Bool {
        didSet {
            capture.isPaused = capturePaused
            settings.setBool("paused", capturePaused)
        }
    }

    /// Wired by the AppDelegate after launch (menu-bar actions call these).
    var openDashboard: (() -> Void)?
    var runJudgeNow: (() -> Void)?
    var startCalm: (() -> Void)?
    var startCalmOffer: (() -> Void)?
    /// Demo hook: set Togi's wellbeing 0…100 to preview the thrive/wilt states live.
    var setVitalityDemo: ((Double) -> Void)?

    init(database: DatabaseService) {
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
        self.planner = PlannerService(repository: plannedBlocks)
        let eventKit = EventKitService()
        self.eventKit = eventKit
        self.calendar = CalendarRouter(eventKit: eventKit, settings: settings)
        self.search = SearchService(
            database: database,
            index: VectorIndex(database: database),
            embedder: AppleSentenceEmbedding()
        )
        let goals = GoalsService(database: database)
        let insights = InsightsService(database: database)
        self.goals = goals
        self.insights = insights
        self.coach = CoachService(
            inference: inference, insights: insights, search: search,
            goals: goals, database: database
        )
        self.judge = JudgeService(inference: inference, segmentStore: segments)

        let paused = settings.bool("paused", default: false)
        self.capturePaused = paused
        capture.isPaused = paused
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
    private let hotkey = VoiceHotkeyMonitor()
    private var voiceCancellables: Set<AnyCancellable> = []

    /// Hands-free "talk to Togi" voice scheduling. Built lazily from app services on first use:
    /// the intent brain reuses the existing inference backend, so it needs no extra key; the
    /// spoken voice upgrades to ElevenLabs when ELEVENLABS_API_KEY is set, else uses macOS speech.
    private lazy var voiceSession = VoiceSession(
        voice: VoiceOutput(settings: appState.settings),
        agent: VoiceCommandAgent { [appState] system, messages in
            try await appState.inference.infer(system: system, messages: messages, maxTokens: 320)
        },
        calendar: appState.calendar
    )

    override init() {
        let db: DatabaseService
        do {
            db = try DatabaseService(path: DatabaseService.defaultPath())
        } catch {
            NSLog("Bogi: failed to open database: \(error). Falling back to in-memory.")
            db = try! DatabaseService(inMemory: true)
        }
        appState = AppState(database: db)
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

        if appState.capture.permissionState != .granted {
            appState.capture.requestPermission()
        }
        appState.capture.start()

        let mascot = MascotPanel()
        mascot.onActivate = { [weak self] in
            guard let self else { return }
            // Engaging Togi counts as acknowledging the nudge: drop the bubble and calm the
            // escalation ladder so the next drift starts gentle again.
            self.presenter.acknowledge(now: Date())
            self.mascot?.clearBubble()
            self.toggleCompanion()
        }
        mascot.show()
        self.mascot = mascot

        let coordinator = JudgeCoordinator(
            judge: appState.judge,
            observations: appState.observations,
            blocks: appState.plannedBlocks,
            presenter: presenter
        ) { [weak self] decision, onTask in
            self?.applyNudge(decision, onTask: onTask)
        }
        coordinator.start()
        self.coordinator = coordinator

        appState.openDashboard = { [weak self] in self?.showCompanion() }
        appState.runJudgeNow = { [weak self] in Task { await self?.coordinator?.tick() } }
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

        // Tap Control anywhere to talk to Togi — no window opens, the floating axolotl is the
        // whole UI. One tap starts a hands-free conversation; tap again or press Esc to stop.
        // Needs Accessibility (same permission the capture loop requests); a real Control
        // shortcut (Control-C, Control-click, etc.) is ignored.
        hotkey.onToggle = { [weak self] in self?.voiceSession.toggleConversation() }
        hotkey.onEscape = { [weak self] in self?.voiceSession.cancel() }
        hotkey.start()

        // Reflect the live voice state on the axolotl: the aura follows the mic while you talk,
        // and Togi's own voice while Togi talks. No text — the glow is the whole visual.
        voiceSession.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] lvl in self?.mascot?.viewModel.voiceLevel = lvl }
            .store(in: &voiceCancellables)
        voiceSession.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.mascot?.viewModel.voiceActive = (phase == .listening || phase == .speaking)
            }
            .store(in: &voiceCancellables)
    }

    private func applyNudge(_ decision: NudgeDecision, onTask: Bool) {
        guard let mascot else { return }
        // Wellbeing rides the real loop: each read nudges Togi toward thriving (on-task)
        // or wilting (off-task). The body's look follows in MascotView.
        mascot.viewModel.nudgeVitality(onTask: onTask)
        if decision.show {
            mascot.apply(decision)
            if decision.playSound { NSSound.beep() }
        } else {
            mascot.update(mood: onTask ? .onTask : .offTask)
        }
    }

    private func companionPanel() -> CompanionPanel {
        if let companion { return companion }
        let state = appState
        let voice = voiceSession
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
                ask: { question in try await state.coach.ask(question) },
                suggest: { state.coach.suggestions() },
                maxContentHeight: maxContentHeight,
                onHeightChange: reportHeight,
                onSettings: { AppDelegate.openSettings() },
                onClose: { [weak self] in
                    self?.companion?.orderOut(nil)
                    self?.voiceSession.cancel()
                },
                seedMessages: seed,
                voice: voice
            )
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
