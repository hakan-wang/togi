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
/// no state. Mirrors the web vitality demo: full of colour and lift when thriving, then
/// desaturated, grey, slumped and sluggish when neglected. Never "dead" — the floor still
/// gently bobs, and it always recovers.
struct VitalityLook {
    let saturation: Double
    let grayscale: Double
    let scale: CGFloat
    let droopY: CGFloat        // sinks down when low, lifts a touch when high
    let bobDistance: CGFloat
    let bobDuration: Double

    init(_ vitality: Double) {
        let v = Swift.max(0, Swift.min(100, vitality))
        let t = v / 100
        saturation  = 0.22 + 0.98 * t                     // drains harder when neglected
        grayscale   = Swift.max(0, (50 - v) / 50 * 0.55)  // greys in earlier (below ~50) and deeper
        scale       = CGFloat(0.92 + 0.13 * t)            // visibly smaller when low, fuller when thriving
        droopY      = CGFloat(14 - 17 * t)                // slumps lower when low, lifts when high
        bobDistance = CGFloat(3 + 7 * t)                  // barely bobs when drained, bouncy when alive
        bobDuration = 5.4 - 2.8 * t                       // sluggish when low, lively when high
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
    /// `VitalityLook`: alive and saturated up high, drained and grey down low.
    @Published var vitality: Double
    /// Live mic input level (0…1) while the user talks to Togi, and whether a voice turn is
    /// recording. Drives the reactive glow behind the axolotl; pushed by the owner.
    @Published var voiceLevel: Float = 0
    @Published var voiceActive: Bool = false
    /// True only while the one-time post-onboarding intro bubble is showing. Drives the dismiss
    /// `×` in `SpeechBubble` and guards the auto-dismiss timer in `MascotPanel`. Nudges never set
    /// this, so ordinary nudge bubbles stay button-less.
    @Published var introActive: Bool = false

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

    /// End the one-time intro: clear the flag and drop the bubble back to a resting state.
    func dismissIntro() {
        introActive = false
        clearBubble()
    }

    /// Nudge wellbeing from a single on-task/off-task read. Gentle on purpose: it takes
    /// sustained follow-through to thrive and a rough patch to wilt, and it always
    /// recovers. Called each judge tick.
    func nudgeVitality(onTask: Bool) {
        vitality = (vitality + (onTask ? 1.6 : -2.8)).clampedToVitality()
    }

    /// Set wellbeing directly (demo control now; real follow-through data later).
    func setVitality(_ value: Double) {
        vitality = value.clampedToVitality()
    }
}

private extension Double {
    func clampedToVitality() -> Double { Swift.max(0, Swift.min(100, self)) }
}
