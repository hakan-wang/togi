import Foundation

/// What the launch gate should show. `checking` is the initial state before the first
/// `AccountGate.check()` resolves.
enum GateState: Equatable {
    case checking
    case needsLogin
    case needsSubscription
    case blocked          // signed in + subscribed unknown (offline / server error)
    case unlocked

    init(for outcome: GateOutcome) {
        switch outcome {
        case .subscribed:    self = .unlocked
        case .notSubscribed: self = .needsSubscription
        case .signedOut:     self = .needsLogin
        case .unreachable:   self = .blocked
        }
    }
}
