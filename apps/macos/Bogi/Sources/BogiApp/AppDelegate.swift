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

    /// Set by the AppDelegate after launch; drives the Calendars settings UI.
    @Published var calendarSync: CalendarSyncCoordinator?

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
        self.eventKit = EventKitService()
        self.googleCalendar = GoogleCalendarService(redirectScheme: GoogleConfig.redirectScheme)
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

        if appState.capture.permissionState != .granted {
            appState.capture.requestPermission()
        }
        appState.capture.start()

        let mascot = MascotPanel()
        mascot.onActivate = { [weak self] in self?.toggleCompanion() }
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

        let calendarSync = CalendarSyncCoordinator(
            google: appState.googleCalendar, planner: appState.planner, settings: appState.settings
        )
        calendarSync.start()
        appState.calendarSync = calendarSync
    }

    private func applyNudge(_ decision: NudgeDecision, onTask: Bool) {
        guard let mascot else { return }
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
        let panel = CompanionPanel {
            CompanionView(
                insight: { period in state.insights.insight(for: period, containing: Date()) },
                ask: { question in try await state.coach.ask(question) },
                onSettings: { AppDelegate.openSettings() },
                onClose: { [weak self] in self?.companion?.orderOut(nil) }
            )
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
