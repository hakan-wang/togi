import Foundation

/// Pure, framework-light state machine driving Bogi's first-run funnel:
///
///     privacy promise → login (paid) → just-in-time Accessibility primer → mascot
///
/// It intentionally has **no** UI, AppKit, or service dependencies so the whole
/// funnel — including the high-risk "Accessibility denied" branch — is unit
/// testable. `OnboardingView` renders the current `OnboardingStep`; `AppDelegate`
/// feeds real events (auth result, permission result) in via `next(from:given:)`.
///
/// The single transition function is total: any event that does not apply to the
/// current step is a no-op that returns the same step, so callers never crash on
/// an out-of-order event (e.g. a late permission callback).
///
/// Types are `internal` (not `public`) because `OnboardingEvent` references the
/// module-internal `PermissionStatus`; everything lives in the `BogiApp` target
/// and tests reach it via `@testable import BogiApp`.
enum OnboardingStep: String, Equatable, CaseIterable {
    /// "We never screenshot or upload" — the trust pitch shown before anything else.
    case privacyPromise
    /// Paid-account login. Unpaid users are pushed to pay on the website.
    case login
    /// Just-in-time Accessibility primer with a deep link into System Settings.
    case accessibilityPrimer
    /// "You're set" — the floating mascot appears. Terminal step.
    case mascot

    /// The funnel's entry point.
    static let first: OnboardingStep = .privacyPromise

    /// True once onboarding is complete and the mascot is shown.
    var isTerminal: Bool { self == .mascot }
}

/// Events that can advance the onboarding funnel. Each carries just enough
/// context to decide the next step; the machine itself stores no other state.
enum OnboardingEvent: Equatable {
    /// User acknowledged the privacy promise and tapped "Continue".
    case acknowledgedPrivacy
    /// Authentication finished. `paid` reflects the `/v1/account/status` gate:
    /// only paid accounts may proceed past login.
    case authenticated(paid: Bool)
    /// The Accessibility permission was resolved to a concrete status (typically
    /// after returning from the system prompt / System Settings).
    case accessibilityResolved(PermissionStatus)
    /// User chose to continue without granting Accessibility. Capture is degraded
    /// until it's granted later, but the mascot still appears so trust is built
    /// immediately (the spec cites ~40% drop at this step).
    case skipAccessibility
}

/// The onboarding state machine. Holds the current step and applies events.
struct OnboardingState: Equatable {
    private(set) var step: OnboardingStep

    init(step: OnboardingStep = .first) {
        self.step = step
    }

    /// True once the mascot is shown and onboarding should be dismissed.
    var isComplete: Bool { step.isTerminal }

    /// Apply an event in place, advancing `step` per the transition table.
    mutating func apply(_ event: OnboardingEvent) {
        step = OnboardingState.next(from: step, given: event)
    }

    /// Pure transition function: the next step given the current step and an
    /// event. Unapplicable events return `from` unchanged (total + side-effect
    /// free), which keeps the machine robust to out-of-order callbacks.
    static func next(from step: OnboardingStep, given event: OnboardingEvent) -> OnboardingStep {
        switch (step, event) {
        // Privacy promise → login once acknowledged.
        case (.privacyPromise, .acknowledgedPrivacy):
            return .login

        // Login → Accessibility primer only for paid accounts. Unpaid stays on
        // login (the UI routes them to pay on the website).
        case (.login, .authenticated(let paid)):
            return paid ? .accessibilityPrimer : .login

        // Accessibility primer → mascot when granted, or when the user explicitly
        // continues without it. Denied / notDetermined keep them on the primer so
        // they can retry or open System Settings.
        case (.accessibilityPrimer, .accessibilityResolved(.granted)):
            return .mascot
        case (.accessibilityPrimer, .skipAccessibility):
            return .mascot
        case (.accessibilityPrimer, .accessibilityResolved(.denied)),
             (.accessibilityPrimer, .accessibilityResolved(.notDetermined)):
            return .accessibilityPrimer

        // Anything else (including any event on the terminal `mascot` step) is a
        // no-op.
        default:
            return step
        }
    }
}
