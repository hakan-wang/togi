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
        case .signedIn:    self = .unlocked
        case .signedOut:   self = .needsLogin
        case .unreachable: self = .blocked
        }
    }
}
