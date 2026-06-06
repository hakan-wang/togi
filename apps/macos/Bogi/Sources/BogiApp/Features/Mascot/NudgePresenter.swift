import Foundation

/// The outcome of asking the presenter how to surface a nudge. Pure value type so
/// it can be asserted directly in tests and applied to the view model by the owner.
struct NudgeDecision: Equatable {
    /// Whether anything should be shown at all (false when snoozed or in DND).
    let show: Bool
    /// 0 = calm bubble. Grows when nudges are ignored, capped at `maxEscalation`.
    let escalationLevel: Int
    /// True once the nudge is loud enough to warrant an audible alert.
    let playSound: Bool
    /// The message to display, or nil when suppressed.
    let text: String?
}

/// Pure, testable decision logic for off-task nudges. No SwiftUI / AppKit imports.
///
/// Behavior (locked design): nudges start as a quiet, non-modal bubble and ESCALATE
/// (bigger + sound) only if the user keeps ignoring them. Snooze and per-block
/// do-not-disturb fully suppress nudges. Acknowledging resets the escalation ladder.
///
/// Escalation rule: each `present(...)` call that arrives within `escalationWindow`
/// of the previous unacknowledged nudge bumps the level by one, up to `maxEscalation`.
/// A call outside the window is treated as a fresh, calm nudge (level 0). Sound plays
/// once the level reaches `soundThreshold`.
final class NudgePresenter {
    // Injected timing constants (defaults chosen per design notes).
    private let escalationWindow: TimeInterval  // e.g. 90s
    private let maxEscalation: Int              // e.g. 3
    private let soundThreshold: Int             // e.g. 2

    // Mutable state.
    private(set) var lastNudgeAt: Date?
    private(set) var currentEscalation: Int = 0
    private(set) var consecutiveIgnored: Int = 0
    private(set) var snoozedUntil: Date?
    private(set) var dndUntil: Date?

    init(escalationWindow: TimeInterval = 90,
         maxEscalation: Int = 3,
         soundThreshold: Int = 2) {
        self.escalationWindow = escalationWindow
        self.maxEscalation = maxEscalation
        self.soundThreshold = soundThreshold
    }

    /// Decide how to present an off-task nudge right now.
    func present(message: String, now: Date) -> NudgeDecision {
        // Suppressed entirely while snoozed or in a do-not-disturb block.
        if isSuppressed(now: now) {
            return NudgeDecision(show: false, escalationLevel: 0, playSound: false, text: nil)
        }

        // Decide escalation: repeated, still-unacknowledged nudges within the window
        // climb the ladder; anything slower resets to a calm first nudge.
        if let last = lastNudgeAt, now.timeIntervalSince(last) <= escalationWindow {
            currentEscalation = min(currentEscalation + 1, maxEscalation)
            consecutiveIgnored += 1
        } else {
            currentEscalation = 0
            consecutiveIgnored = 0
        }

        lastNudgeAt = now
        let playSound = currentEscalation >= soundThreshold
        return NudgeDecision(
            show: true,
            escalationLevel: currentEscalation,
            playSound: playSound,
            text: message
        )
    }

    /// User engaged with the nudge (clicked the mascot, replied, got back on task).
    /// Resets the escalation ladder so the next nudge starts calm again.
    func acknowledge(now: Date) {
        currentEscalation = 0
        consecutiveIgnored = 0
        lastNudgeAt = nil
    }

    /// Suppress nudges for `minutes` from `now`.
    func snooze(minutes: Int, now: Date) {
        snoozedUntil = now.addingTimeInterval(TimeInterval(minutes) * 60)
        // Snoozing is an implicit acknowledgement — reset the ladder.
        currentEscalation = 0
        consecutiveIgnored = 0
        lastNudgeAt = nil
    }

    /// Per-block do-not-distract: suppress nudges until the given instant.
    func setDND(until: Date) {
        dndUntil = until
    }

    /// Lift any active do-not-disturb block.
    func clearDND() {
        dndUntil = nil
    }

    /// True if nudges are currently suppressed by snooze or DND.
    func isSuppressed(now: Date) -> Bool {
        if let s = snoozedUntil, now < s { return true }
        if let d = dndUntil, now < d { return true }
        return false
    }
}
