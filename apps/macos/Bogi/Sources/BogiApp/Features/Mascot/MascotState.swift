import Foundation
import SwiftUI

/// The mascot's visible mood. Drives color/expression in `MascotView`.
enum MascotMood {
    case idle      // neutral resting state, no signal
    case onTask    // user is focused — happy
    case offTask   // user has drifted — concerned
    case speaking  // actively delivering a nudge
}

/// Cosmetic mapping from `vitality` (0…100) to how the mascot body reads. Pure function,
/// no state. One signal, one colour shift: Togi stays baby-blue when thriving and flushes
/// toward a deep red the more unproductive (lower vitality) it gets. The plush shading is
/// preserved — we only recolour, never desaturate or slump it.
struct VitalityLook {
    /// 0 = thriving (baby-blue) … 1 = neglected (deep red).
    let redness: Double
    /// Eased strength of the red overlay — ramps in a touch faster than linear.
    let washOpacity: Double

    init(_ vitality: Double) {
        let v = Swift.max(0, Swift.min(100, vitality))
        redness = (100 - v) / 100
        washOpacity = pow(redness, 0.85)
    }
}

/// Thin observable state for the mascot UI. Holds no decision logic — escalation,
/// snooze and DND all live in `NudgePresenter`. The view model is just the bridge
/// that SwiftUI observes; the AppDelegate (or owner) pushes values into it.
@MainActor
final class MascotViewModel: ObservableObject {
    @Published var mood: MascotMood
    @Published var bubbleText: String?
    /// 0 = calm. Higher means a louder/bigger nudge (see `NudgePresenter`).
    @Published var escalationLevel: Int
    /// Togi's wellbeing, 0 (neglected) … 100 (thriving). Climbs when the user follows
    /// through (on-task), drifts down when off-task or idle. Drives the body's look via
    /// `VitalityLook`: baby-blue up high, flushing toward deep red down low.
    @Published var vitality: Double
    /// Live mic input level (0…1) while the user talks to Togi, and whether a voice turn is
    /// recording. Drives the reactive glow behind the axolotl; pushed by the owner.
    @Published var voiceLevel: Float = 0
    @Published var voiceActive: Bool = false

    init(mood: MascotMood = .idle,
         bubbleText: String? = nil,
         escalationLevel: Int = 0,
         vitality: Double = 70) {
        self.mood = mood
        self.bubbleText = bubbleText
        self.escalationLevel = escalationLevel
        self.vitality = vitality
    }

    /// Apply a presenter decision to the visible state.
    func apply(_ decision: NudgeDecision) {
        if decision.show {
            mood = .speaking
            bubbleText = decision.text
            escalationLevel = decision.escalationLevel
        }
        // If a decision says don't show (snoozed/DND), leave the current bubble
        // untouched — the owner decides whether to clear it via `clearBubble()`.
    }

    /// Drop the speech bubble and fall back to a resting mood.
    func clearBubble(fallback: MascotMood = .idle) {
        bubbleText = nil
        escalationLevel = 0
        mood = fallback
    }

    /// Nudge wellbeing from a single on-task/off-task read. Gentle on purpose: it takes
    /// sustained follow-through to thrive and a rough patch to wilt, and it always
    /// recovers. Called each judge tick.
    func nudgeVitality(onTask: Bool) {
        vitality = (vitality + (onTask ? 1.6 : -2.2)).clampedToVitality()
    }

    /// Set wellbeing directly (demo control now; real follow-through data later).
    func setVitality(_ value: Double) {
        vitality = value.clampedToVitality()
    }
}

private extension Double {
    func clampedToVitality() -> Double { Swift.max(0, Swift.min(100, self)) }
}
