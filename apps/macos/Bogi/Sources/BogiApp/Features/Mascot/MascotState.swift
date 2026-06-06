import Foundation
import SwiftUI

/// The mascot's visible mood. Drives color/expression in `MascotView`.
enum MascotMood {
    case idle      // neutral resting state, no signal
    case onTask    // user is focused — happy
    case offTask   // user has drifted — concerned
    case speaking  // actively delivering a nudge
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

    init(mood: MascotMood = .idle,
         bubbleText: String? = nil,
         escalationLevel: Int = 0) {
        self.mood = mood
        self.bubbleText = bubbleText
        self.escalationLevel = escalationLevel
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
}
