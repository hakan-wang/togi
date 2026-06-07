import Foundation

/// Owns the 5-minute judge heartbeat: gather the last 5 min of activity + the active
/// planned block and forward them to the on-device agent. The agent segments the activity
/// (via `record_segments`), compares against history, and nudges (via `post_nudge`) — all
/// in one loop. This coordinator only schedules ticks and builds the payload.
@MainActor
final class JudgeCoordinator {
    private let observations: ObservationStore
    private let blocks: PlannedBlockRepository
    private let segments: SegmentStore
    private let sidecar: SidecarClient
    private let events: UserEventRepository?
    private let goals: GoalsService?
    private let interval: TimeInterval
    /// Rolling window for the off-task minutes fed into nudge urgency (60 min).
    private let offTaskWindow: TimeInterval = 3600
    private var timer: DispatchSourceTimer?

    init(observations: ObservationStore,
         blocks: PlannedBlockRepository,
         segments: SegmentStore,
         sidecar: SidecarClient,
         events: UserEventRepository? = nil,
         goals: GoalsService? = nil,
         interval: TimeInterval = 300) {
        self.observations = observations
        self.blocks = blocks
        self.segments = segments
        self.sidecar = sidecar
        self.events = events
        self.goals = goals
        self.interval = interval
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in Task { @MainActor in await self?.tick() } }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// One judge cycle. Public so a "Check in now" action can trigger it on demand. Runs when
    /// there are recent observations OR a check-in is due (so proactive check-ins fire even on a
    /// quiet screen).
    func tick() async {
        let now = Date()
        let recent = observations.recent(within: interval, now: now)
        let due = events?.dueCheckIns(asOf: now) ?? []
        guard !recent.isEmpty || !due.isEmpty else { return }

        let obs = recent.map {
            (t: $0.capturedAt, app: $0.activeApp, window: $0.activeWindowTitle,
             text: $0.text, focused: $0.focused)
        }
        let active = blocks.activeBlock(at: now)
        let activeEvents = (events?.events(overlapping: now) ?? [])
            .filter { $0.goalId == nil }
            .map { (title: $0.title, cat: $0.cat, startAt: $0.startAt, endAt: $0.endAt) }
        var input = JudgeInput(
            activeBlock: active.map { (title: $0.title, cat: $0.cat, startAt: $0.startAt, endAt: $0.endAt) },
            observations: obs,
            recentOffTaskMinutes: segments.offTaskMinutes(within: offTaskWindow, now: now),
            activeEvents: activeEvents
        )
        input.activeGoals = goals?.all(status: "active").map {
            (id: $0.id, title: $0.title, status: $0.status, cat: $0.cat)
        } ?? []
        input.dueCheckIns = due.map { (eventId: $0.id, goalId: $0.goalId, title: $0.title) }

        let payload = JudgePrompt.userJSON(input)
        let reply = try? await sidecar.judge(payload, threadId: "judge")
        // Surface each due check-in once, but only remove it after a successful dispatch so a
        // transport failure does not silently drop it. Recurrence is the agent scheduling the
        // next add_event when it logs the check-in outcome.
        if reply != nil { due.forEach { events?.delete(id: $0.id) } }
    }
}
