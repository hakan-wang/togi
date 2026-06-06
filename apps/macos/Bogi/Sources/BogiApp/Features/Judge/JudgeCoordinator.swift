import Foundation

/// Owns the 5-minute judge heartbeat: gather the last 5 min of activity + the active
/// planned block and forward them to the on-device agent. The agent segments the activity
/// (via `record_segments`), compares against history, and nudges (via `post_nudge`) — all
/// in one loop. This coordinator only schedules ticks and builds the payload.
@MainActor
final class JudgeCoordinator {
    private let observations: ObservationStore
    private let blocks: PlannedBlockRepository
    private let sidecar: SidecarClient
    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?

    init(observations: ObservationStore,
         blocks: PlannedBlockRepository,
         sidecar: SidecarClient,
         interval: TimeInterval = 300) {
        self.observations = observations
        self.blocks = blocks
        self.sidecar = sidecar
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

    /// One judge cycle. Public so a "Check in now" action can trigger it on demand.
    func tick() async {
        let now = Date()
        let recent = observations.recent(within: interval, now: now)
        guard !recent.isEmpty else { return }

        let obs = recent.map {
            (t: $0.capturedAt, app: $0.activeApp, window: $0.activeWindowTitle,
             text: $0.text, focused: $0.focused)
        }
        let active = blocks.activeBlock(at: now)
        let input = JudgeInput(
            activeBlock: active.map { (title: $0.title, category: $0.category, startAt: $0.startAt, endAt: $0.endAt) },
            observations: obs,
            recentOffTaskMinutes: 0
        )
        let payload = JudgePrompt.userJSON(input)
        _ = try? await sidecar.judge(payload, threadId: "judge")
    }
}
