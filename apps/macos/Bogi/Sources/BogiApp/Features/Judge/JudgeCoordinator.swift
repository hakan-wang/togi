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
    private let nudgeGate: NudgeGate
    private let sidecar: SidecarClient
    private let interval: TimeInterval
    private let onResult: (NudgeDecision, _ onTask: Bool) -> Void
    private var timer: DispatchSourceTimer?

    init(judge: JudgeService,
         observations: ObservationStore,
         blocks: PlannedBlockRepository,
         presenter: NudgePresenter,
         nudgeGate: NudgeGate,
         sidecar: SidecarClient,
         interval: TimeInterval = 300,
         onResult: @escaping (NudgeDecision, Bool) -> Void) {
        self.judge = judge
        self.observations = observations
        self.blocks = blocks
        self.presenter = presenter
        self.nudgeGate = nudgeGate
        self.sidecar = sidecar
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
            (t: $0.capturedAt, app: $0.activeApp, window: $0.activeWindowTitle,
             text: $0.text, focused: $0.focused)
        }
        let active = blocks.activeBlock(at: now)
        let input = JudgeInput(
            activeBlock: active.map { (title: $0.title, category: $0.category, startAt: $0.startAt, endAt: $0.endAt) },
            observations: obs,
            recentOffTaskMinutes: 0
        )

        guard let run = try? await judge.runOnce(input: input) else { return }

        // Cheap deterministic gate: only pay for an agent invocation when we are plausibly
        // off-task against an active plan. Otherwise just update the mascot mood.
        let consider = nudgeGate.shouldConsiderNudge(segments: run.segments, hasActivePlan: active != nil)
        onResult(NudgeDecision(show: false, escalationLevel: 0, playSound: false, text: nil), !consider)
        guard consider else { return }

        // Hand the drift summary to the agent on an ephemeral thread. The agent decides
        // whether (and how) to nudge by calling the post_nudge action tool.
        let summary = Self.nudgeSummary(active: active, segments: run.segments, now: now)
        _ = try? await sidecar.plan(summary, threadId: "nudge")
    }

    /// Compact, model-facing summary of the last interval's drift. Pure + testable.
    static func nudgeSummary(active: PlannedBlock?, segments: [JudgeSegment], now: Date) -> String {
        let off = segments.filter { $0.onTask == false }
            .map { $0.subSub ?? $0.subCategory ?? $0.category ?? "something else" }
        let plan = active?.title ?? "no specific plan"
        return "In the last 5 minutes the user planned '\(plan)' but spent time on: " +
               off.joined(separator: ", ") +
               ". If this is a real drift, call post_nudge with a kind, supportive message. Otherwise do nothing."
    }
}
