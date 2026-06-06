import XCTest
@testable import BogiApp

final class OnboardingTests: XCTestCase {

    // MARK: Happy path

    func testHappyPathReachesMascot() {
        var state = OnboardingState()
        XCTAssertEqual(state.step, .privacyPromise)
        XCTAssertFalse(state.isComplete)

        state.apply(.acknowledgedPrivacy)
        XCTAssertEqual(state.step, .login)

        state.apply(.authenticated(paid: true))
        XCTAssertEqual(state.step, .accessibilityPrimer)

        state.apply(.accessibilityResolved(.granted))
        XCTAssertEqual(state.step, .mascot)
        XCTAssertTrue(state.isComplete)
        XCTAssertTrue(state.step.isTerminal)
    }

    func testNextPureFunctionHappyPath() {
        XCTAssertEqual(
            OnboardingState.next(from: .privacyPromise, given: .acknowledgedPrivacy),
            .login
        )
        XCTAssertEqual(
            OnboardingState.next(from: .login, given: .authenticated(paid: true)),
            .accessibilityPrimer
        )
        XCTAssertEqual(
            OnboardingState.next(from: .accessibilityPrimer, given: .accessibilityResolved(.granted)),
            .mascot
        )
    }

    // MARK: Accessibility-denied branch

    func testAccessibilityDeniedKeepsUserOnPrimer() {
        var state = OnboardingState(step: .accessibilityPrimer)

        state.apply(.accessibilityResolved(.denied))
        XCTAssertEqual(state.step, .accessibilityPrimer, "denied must not advance past the primer")
        XCTAssertFalse(state.isComplete)

        // notDetermined (e.g. user dismissed the prompt) also stays put.
        state.apply(.accessibilityResolved(.notDetermined))
        XCTAssertEqual(state.step, .accessibilityPrimer)

        // Retrying and granting from the denied state still proceeds.
        state.apply(.accessibilityResolved(.granted))
        XCTAssertEqual(state.step, .mascot)
        XCTAssertTrue(state.isComplete)
    }

    func testAccessibilityDeniedThenSkipReachesMascot() {
        var state = OnboardingState(step: .accessibilityPrimer)

        state.apply(.accessibilityResolved(.denied))
        XCTAssertEqual(state.step, .accessibilityPrimer)

        // User can continue without granting; the mascot still appears.
        state.apply(.skipAccessibility)
        XCTAssertEqual(state.step, .mascot)
        XCTAssertTrue(state.isComplete)
    }

    // MARK: Unpaid login branch

    func testUnpaidLoginStaysOnLogin() {
        var state = OnboardingState(step: .login)
        state.apply(.authenticated(paid: false))
        XCTAssertEqual(state.step, .login, "unpaid accounts cannot pass the login gate")
        XCTAssertFalse(state.isComplete)

        // Becoming paid then advances.
        state.apply(.authenticated(paid: true))
        XCTAssertEqual(state.step, .accessibilityPrimer)
    }

    // MARK: Totality / robustness to out-of-order events

    func testInapplicableEventsAreNoOps() {
        // A late permission callback while still on the privacy screen.
        XCTAssertEqual(
            OnboardingState.next(from: .privacyPromise, given: .accessibilityResolved(.granted)),
            .privacyPromise
        )
        // Acknowledging privacy again from the login screen.
        XCTAssertEqual(
            OnboardingState.next(from: .login, given: .acknowledgedPrivacy),
            .login
        )
        // Auth result arriving before the privacy promise is acknowledged.
        XCTAssertEqual(
            OnboardingState.next(from: .privacyPromise, given: .authenticated(paid: true)),
            .privacyPromise
        )
    }

    func testTerminalMascotStepIsAbsorbing() {
        let events: [OnboardingEvent] = [
            .acknowledgedPrivacy,
            .authenticated(paid: true),
            .authenticated(paid: false),
            .accessibilityResolved(.granted),
            .accessibilityResolved(.denied),
            .skipAccessibility
        ]
        for event in events {
            XCTAssertEqual(
                OnboardingState.next(from: .mascot, given: event),
                .mascot,
                "no event should move the funnel off the terminal mascot step"
            )
        }
    }

    func testFullFunnelViaNextChaining() {
        var step = OnboardingStep.first
        step = OnboardingState.next(from: step, given: .acknowledgedPrivacy)
        step = OnboardingState.next(from: step, given: .authenticated(paid: true))
        step = OnboardingState.next(from: step, given: .accessibilityResolved(.granted))
        XCTAssertEqual(step, .mascot)
    }
}
