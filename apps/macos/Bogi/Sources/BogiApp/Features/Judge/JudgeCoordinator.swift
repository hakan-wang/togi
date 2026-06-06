import Foundation

/// Owns the 5-minute judge heartbeat: gather the last 5 min of activity + the active
/// planned block, run the judge, and route the nudge decision out (to the mascot).
/// Scheduling lives here so `JudgeService` stays pure/testable.
@MainActor
final class JudgeCoordinator {
    private let judge: JudgeService
    private let observations: ObservationStore
    private let blocks: PlannedBlockRepository
    private let presenter: NudgePresenter
    private let interval: TimeInterval
    private let onResult: (NudgeDecision, _ onTask: Bool) -> Void
    private var timer: DispatchSourceTimer?

    init(judge: JudgeService,
         observations: ObservationStore,
         blocks: PlannedBlockRepository,
         presenter: NudgePresenter,
         interval: TimeInterval = 300,
         onResult: @escaping (NudgeDecision, Bool) -> Void) {
        self.judge = judge
        self.observations = observations
        self.blocks = blocks
        self.presenter = presenter
        self.interval = interval
        self.onResult = onResult
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
            (t: $0.capturedAt, app: $0.activeApp, window: $0.activeWindowTitle, text: $0.text)
        }
        let active = blocks.activeBlock(at: now)
        let input = JudgeInput(
            activeBlock: active.map { (title: $0.title, category: $0.category, startAt: $0.startAt, endAt: $0.endAt) },
            observations: obs,
            recentOffTaskMinutes: 0
        )

        guard let nudge = try? await judge.runOnce(input: input) else { return }
        let onTask = !nudge.should
        if nudge.should, let message = nudge.message {
            onResult(presenter.present(message: message, now: now), onTask)
        } else {
            onResult(NudgeDecision(show: false, escalationLevel: 0, playSound: false, text: nil), onTask)
        }
    }
}
