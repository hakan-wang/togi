import Foundation
import GRDB

/// Thin entry point the judge (Phase 5) uses to hand a composed nudge to the
/// mascot. Implemented by `NudgePresenter`; kept as a protocol so the judge can
/// be built and tested against a mock without depending on AppKit. Main-actor
/// isolated because surfacing a nudge drives UI.
@MainActor
public protocol NudgeSink: AnyObject {
    func present(_ nudge: Nudge)
}

/// Opens the on-demand coach chat anchored to the mascot. The mascot module does
/// NOT depend on the coach session — an integrator supplies a concrete
/// implementation (Phase 7) and wires it in. Defined here so click / "Hey Bogi"
/// can request the coach without a hard dependency.
@MainActor
public protocol CoachPresenting: AnyObject {
    func presentCoach(anchoredTo anchor: MascotAnchor, prompt: String?)
}

/// Renders / hides the non-modal speech bubble. The production implementation
/// drives the SwiftUI bubble inside `MascotPanel`; tests use a spy so the
/// presenter's policy logic stays verifiable without a window server.
@MainActor
public protocol NudgeBubblePresenting: AnyObject {
    func showBubble(message: String, decision: NudgeDecision)
    func hideBubble()
}

/// Persists a nudge's shown timestamp and resolved outcome. Backed by GRDB in
/// production (`DatabaseNudgeOutcomeStore`); tests use an in-memory spy or the
/// real in-memory `DatabaseService`.
public protocol NudgeOutcomeStore: AnyObject {
    /// Stamp `shown_at` when the nudge first reaches the user (outcome untouched).
    func markShown(nudgeId: String, at: Date)
    /// Set the resolved `outcome`.
    func record(nudgeId: String, outcome: NudgeOutcome)
}

/// Where on screen to anchor the coach chat — the mascot's current frame in
/// screen coordinates. Framework-light (`Double` fields) so it carries no
/// AppKit dependency across the module boundary.
public struct MascotAnchor: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// GRDB-backed outcome store. Loads the `Nudge` row by id and updates it.
public final class DatabaseNudgeOutcomeStore: NudgeOutcomeStore {
    private let database: DatabaseService

    public init(database: DatabaseService) {
        self.database = database
    }

    public func markShown(nudgeId: String, at date: Date) {
        try? database.dbQueue.write { db in
            guard var nudge = try Nudge.fetchOne(db, key: nudgeId) else { return }
            // Only stamp the first time it's shown so escalation re-shows don't
            // overwrite the original surfacing time.
            if nudge.shownAt == nil {
                nudge.shownAt = date
                try nudge.update(db)
            }
        }
    }

    public func record(nudgeId: String, outcome: NudgeOutcome) {
        try? database.dbQueue.write { db in
            guard var nudge = try Nudge.fetchOne(db, key: nudgeId) else { return }
            nudge.outcome = outcome
            try nudge.update(db)
        }
    }
}

/// Coordinates surfacing a `Nudge` as a calm → escalating speech bubble.
///
/// The presenter is intentionally thin: all of the "show? how loud? sound?"
/// decisions are delegated to the pure `NudgePolicy`. The presenter only tracks
/// cross-tick state (how many nudges the user has ignored, the snooze deadline),
/// drives the (abstract) bubble, and records the resolved `outcome` to the DB.
///
/// It never blocks the screen: a nudge is at most a non-modal bubble that the
/// user can ignore, snooze, dismiss, or click to talk to Bogi.
@MainActor
public final class NudgePresenter: NudgeSink {
    private let policy: NudgePolicy
    private let bubble: NudgeBubblePresenting
    private let outcomes: NudgeOutcomeStore
    /// Optional — the coach is wired in during integration.
    public weak var coach: CoachPresenting?
    /// Injectable clock for deterministic tests.
    private let clock: () -> Date
    /// Per-block DND windows, re-read each tick (planned blocks change).
    private let dndWindowsProvider: () -> [DNDWindow]
    /// Global DND toggle, re-read each tick (settings `dnd`).
    private let globalDNDProvider: () -> Bool

    /// How many nudges in the current drift the user has ignored so far.
    public private(set) var ignoredTicks: Int = 0
    /// The nudge currently on screen (awaiting a user outcome), if any.
    public private(set) var activeNudge: Nudge?
    /// Current snooze deadline.
    public private(set) var snooze: SnoozeState = SnoozeState()
    /// The most recent decision — exposed for tests / debugging.
    public private(set) var lastDecision: NudgeDecision?

    public init(
        policy: NudgePolicy = NudgePolicy(),
        bubble: NudgeBubblePresenting,
        outcomes: NudgeOutcomeStore,
        coach: CoachPresenting? = nil,
        dndWindowsProvider: @escaping () -> [DNDWindow] = { [] },
        globalDNDProvider: @escaping () -> Bool = { false },
        clock: @escaping () -> Date = Date.init
    ) {
        self.policy = policy
        self.bubble = bubble
        self.outcomes = outcomes
        self.coach = coach
        self.dndWindowsProvider = dndWindowsProvider
        self.globalDNDProvider = globalDNDProvider
        self.clock = clock
    }

    // MARK: - NudgeSink

    /// Surface (or suppress) a nudge handed over by the judge.
    public func present(_ nudge: Nudge) {
        let now = clock()
        let context = NudgeContext(
            ignoredTicks: ignoredTicks,
            now: now,
            snooze: snooze,
            dndWindows: dndWindowsProvider(),
            globalDND: globalDNDProvider()
        )
        let decision = policy.decide(context)
        lastDecision = decision

        guard decision.show else {
            // Snooze / DND: it never reached the user, so we leave the row's
            // outcome untouched and keep the ignored-tick streak as-is.
            bubble.hideBubble()
            return
        }

        activeNudge = nudge
        bubble.showBubble(message: nudge.message, decision: decision)
        outcomes.markShown(nudgeId: nudge.id, at: now)
        // Escalation is itself a recorded outcome: the nudge grew/sounded because
        // the user kept ignoring it. User interaction (dismiss/heeded/snooze) will
        // overwrite this if/when it happens.
        if decision.severity > .calm {
            outcomes.record(nudgeId: nudge.id, outcome: .escalated)
        }

        // This presentation counts as "ignored" for the next tick unless the user
        // resolves it via dismiss / snooze / heeded.
        ignoredTicks += 1
    }

    // MARK: - User interactions

    /// User closed the bubble without changing behaviour.
    public func dismiss() {
        resolve(.dismissed)
    }

    /// User went back on-task (the judge detected on-task again).
    public func heeded() {
        resolve(.heeded)
    }

    /// User asked to be left alone for `duration` (defaults to the policy's
    /// standard snooze). Suppresses subsequent nudges until the deadline.
    public func snoozeCurrent(for duration: TimeInterval? = nil) {
        let now = clock()
        let length = duration ?? policy.config.snoozeDuration
        snooze = SnoozeState(until: now.addingTimeInterval(length))
        resolve(.snoozed)
    }

    /// Click on the fish or the "Hey Bogi" hotkey: open the coach anchored to the
    /// mascot. Treated as engagement, so any active nudge is marked `heeded`.
    public func openCoach(anchoredTo anchor: MascotAnchor, prompt: String? = nil) {
        if activeNudge != nil {
            resolve(.heeded)
        }
        coach?.presentCoach(anchoredTo: anchor, prompt: prompt)
    }

    // MARK: - Private

    private func resolve(_ outcome: NudgeOutcome) {
        if let nudge = activeNudge {
            outcomes.record(nudgeId: nudge.id, outcome: outcome)
        }
        activeNudge = nil
        ignoredTicks = 0
        bubble.hideBubble()
    }
}
