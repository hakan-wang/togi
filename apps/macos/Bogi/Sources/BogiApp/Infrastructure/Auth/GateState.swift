import Foundation

/// What the launch gate should show. `checking` is the initial state before the first
/// `AccountGate.check()` resolves.
enum GateState: Equatable {
    case checking
    case needsLogin
    case blocked          // signed in unknown (offline / server error)
    case unlocked

    init(for outcome: GateOutcome) {
        switch outcome {
        // Freemium: the app is free and the mascot is part of the free tier, so every
        // outcome unlocks the main experience. A signed-out or temporarily-unreachable
        // user still gets in and sees Togi — there is no login or subscription wall in
        // front of the app. Sign-in stays available in Settings → Account for users who
        // want AI and cross-device sync; AI usage limits are enforced server-side per request.
        case .signedIn:    self = .unlocked
        case .signedOut:   self = .unlocked
        case .unreachable: self = .unlocked
        }
    }
}
