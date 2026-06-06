import Foundation

/// The mascot's visible mood. Drives the fish animation in `MascotPanel` and is
/// derived purely from app state by `MascotState.mood(for:)`.
public enum MascotMood: String, Equatable, CaseIterable {
    /// User is active and working on what they planned. Calm, content fish.
    case onTask
    /// User is active but drifting from the plan. Alert, side-eye fish.
    case offTask
    /// No recent activity / capture paused / outcome unknown. Sleepy, still.
    case idle
    /// Bogi is talking to the user (coach chat open or a nudge bubble showing).
    case speaking
}

/// The signals the mascot derives its mood from. Produced by higher layers — the
/// judge supplies the latest on/off-task outcome, capture supplies activity, and
/// the coach/nudge presenter supplies `isSpeaking`. Kept framework-light and
/// `Equatable` so the mapping is trivially unit-testable.
public struct MascotInput: Equatable {
    /// The coach chat is open or a nudge speech-bubble is currently shown.
    public var isSpeaking: Bool
    /// Capture is running and the user has been active recently (not idle).
    public var isActive: Bool
    /// Latest judged on/off-task signal. `nil` when unknown (no recent segment).
    public var onTask: Bool?

    public init(isSpeaking: Bool = false, isActive: Bool = false, onTask: Bool? = nil) {
        self.isSpeaking = isSpeaking
        self.isActive = isActive
        self.onTask = onTask
    }

    /// Nothing known yet (app just launched / capture paused).
    public static let unknown = MascotInput(isSpeaking: false, isActive: false, onTask: nil)
}

/// Pure mapping from app state to mascot mood. No AppKit, no side effects — this
/// is the single source of truth the panel renders from, so it can be exhaustively
/// tested without a window server.
public enum MascotState {
    /// Derive the mascot's mood from the current app state.
    ///
    /// Priority order (highest first):
    /// 1. `speaking` — if Bogi is actively talking, that always wins.
    /// 2. `idle` — if the user is inactive or there is no known on/off-task signal.
    /// 3. `offTask` / `onTask` — otherwise reflect the latest judged outcome.
    public static func mood(for input: MascotInput) -> MascotMood {
        if input.isSpeaking { return .speaking }
        guard input.isActive, let onTask = input.onTask else { return .idle }
        return onTask ? .onTask : .offTask
    }
}
