import Foundation

/// How loud/large a nudge is. The mascot starts `calm` (a quiet, non-modal
/// bubble) and only grows + plays a sound once the user has ignored it for a
/// sustained stretch — never a screen-blocking wall (explicit spec guardrail).
public enum NudgeSeverity: Int, Comparable, Equatable, CaseIterable {
    /// Quiet, small, non-modal bubble. No sound.
    case calm = 0
    /// Larger bubble + sound — the user has been ignoring the calm nudge.
    case firm = 1
    /// Largest bubble + sound — enough to break a real doomscroll.
    case loud = 2

    public static func < (lhs: NudgeSeverity, rhs: NudgeSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Tunable escalation thresholds. Defaults match the spec's "calm → escalating"
/// curve: stay quiet for the first few ignored ticks, then grow + sound.
public struct NudgePolicyConfig: Equatable {
    /// Ignored ticks before the nudge first escalates (grows + sound): the "N".
    public var escalateAfterIgnoredTicks: Int
    /// Ignored ticks before the second, loudest escalation step.
    public var maxEscalationTicks: Int
    /// Default suppression duration applied when the user snoozes.
    public var snoozeDuration: TimeInterval

    public init(escalateAfterIgnoredTicks: Int, maxEscalationTicks: Int, snoozeDuration: TimeInterval) {
        self.escalateAfterIgnoredTicks = escalateAfterIgnoredTicks
        self.maxEscalationTicks = maxEscalationTicks
        self.snoozeDuration = snoozeDuration
    }

    /// Quiet for 3 ignored ticks, escalate at 3, peak at 6, 15-minute snooze.
    public static let standard = NudgePolicyConfig(
        escalateAfterIgnoredTicks: 3,
        maxEscalationTicks: 6,
        snoozeDuration: 15 * 60
    )
}

/// A do-not-disturb window, typically derived from a planned block the user
/// asked Bogi not to interrupt (e.g. a focus meeting).
public struct DNDWindow: Equatable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// Half-open `[start, end)` so back-to-back windows don't double-count.
    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// Snooze state: nudges are fully suppressed until `until`.
public struct SnoozeState: Equatable {
    /// `nil` means not snoozed; otherwise nudges are suppressed until this instant.
    public var until: Date?

    public init(until: Date? = nil) {
        self.until = until
    }

    public func isActive(at now: Date) -> Bool {
        guard let until else { return false }
        return now < until
    }
}

/// Everything the policy needs to decide on a single nudge tick. Pure value
/// type so decisions are deterministic and testable.
public struct NudgeContext: Equatable {
    /// How many prior nudges in this drift the user has ignored (0 on first show).
    public var ignoredTicks: Int
    /// "Now" — injected so tests can pin time.
    public var now: Date
    /// Current snooze state.
    public var snooze: SnoozeState
    /// Per-block DND windows; any window containing `now` suppresses the nudge.
    public var dndWindows: [DNDWindow]
    /// Global do-not-disturb toggle (settings `dnd`).
    public var globalDND: Bool

    public init(
        ignoredTicks: Int,
        now: Date,
        snooze: SnoozeState = SnoozeState(),
        dndWindows: [DNDWindow] = [],
        globalDND: Bool = false
    ) {
        self.ignoredTicks = ignoredTicks
        self.now = now
        self.snooze = snooze
        self.dndWindows = dndWindows
        self.globalDND = globalDND
    }
}

/// The policy's verdict for one tick.
public struct NudgeDecision: Equatable {
    /// Whether to surface the nudge at all.
    public var show: Bool
    /// How loud/large to render it.
    public var severity: NudgeSeverity
    /// Whether to play the escalation sound.
    public var playSound: Bool
    /// Relative visual scale for the bubble/mascot (1.0 = calm baseline).
    public var scale: Double
    /// Why the nudge was suppressed, when `show == false`.
    public var suppression: Suppression?

    public enum Suppression: String, Equatable {
        case snoozed
        case dnd
    }

    public init(show: Bool, severity: NudgeSeverity, playSound: Bool, scale: Double, suppression: Suppression?) {
        self.show = show
        self.severity = severity
        self.playSound = playSound
        self.scale = scale
        self.suppression = suppression
    }

    static let suppressedSnoozed = NudgeDecision(
        show: false, severity: .calm, playSound: false, scale: 1.0, suppression: .snoozed
    )
    static let suppressedDND = NudgeDecision(
        show: false, severity: .calm, playSound: false, scale: 1.0, suppression: .dnd
    )
}

/// PURE escalation / snooze / DND policy — the testable core of the mascot.
/// Given the count of ignored ticks, snooze state, per-block DND windows and the
/// current time, it decides whether to show a nudge, how big/loud, and whether
/// to play a sound. It never decides to block the screen.
public struct NudgePolicy {
    public var config: NudgePolicyConfig

    public init(config: NudgePolicyConfig = .standard) {
        self.config = config
    }

    /// Decide what to do for one nudge tick.
    public func decide(_ context: NudgeContext) -> NudgeDecision {
        // DND wins over everything: per-block windows and the global toggle fully
        // suppress so we never interrupt a window the user protected.
        if context.globalDND || context.dndWindows.contains(where: { $0.contains(context.now) }) {
            return .suppressedDND
        }
        // An active snooze suppresses until it expires.
        if context.snooze.isActive(at: context.now) {
            return .suppressedSnoozed
        }
        let severity = severity(forIgnoredTicks: context.ignoredTicks)
        return NudgeDecision(
            show: true,
            severity: severity,
            // Sound turns on exactly at the first escalation step (the "N") and
            // stays on for louder steps — no sound while still calm.
            playSound: severity > .calm,
            scale: scale(for: severity),
            suppression: nil
        )
    }

    /// Map ignored-tick count to severity. Below `escalateAfterIgnoredTicks` the
    /// nudge stays `calm`; at/above it escalates to `firm`, and at/above
    /// `maxEscalationTicks` to `loud`.
    public func severity(forIgnoredTicks ticks: Int) -> NudgeSeverity {
        if ticks >= config.maxEscalationTicks { return .loud }
        if ticks >= config.escalateAfterIgnoredTicks { return .firm }
        return .calm
    }

    /// Visual scale multiplier for a severity (calm baseline = 1.0).
    public func scale(for severity: NudgeSeverity) -> Double {
        switch severity {
        case .calm: return 1.0
        case .firm: return 1.5
        case .loud: return 2.0
        }
    }
}
