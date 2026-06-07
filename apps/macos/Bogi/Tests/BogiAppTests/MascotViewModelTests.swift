import XCTest
@testable import BogiApp

/// The intro bubble is a one-time, dismissable callout shown right after onboarding. `introActive`
/// tells the view to render a dismiss `×` and guards the auto-dismiss timer; `dismissIntro()` tears
/// the whole thing down. Nudges must never set `introActive`, so nudge bubbles stay button-less.
@MainActor
final class MascotViewModelTests: XCTestCase {
    func testDismissIntroClearsBubbleAndFlag() {
        let vm = MascotViewModel()
        vm.introActive = true
        vm.bubbleText = "Click me anytime."
        vm.escalationLevel = 0
        vm.mood = .speaking

        vm.dismissIntro()

        XCTAssertFalse(vm.introActive, "dismissIntro clears the intro flag")
        XCTAssertNil(vm.bubbleText, "dismissIntro drops the bubble text")
        XCTAssertEqual(vm.escalationLevel, 0, "dismissIntro resets escalation")
    }

    func testNudgeDoesNotActivateIntro() {
        let vm = MascotViewModel()
        let decision = NudgeDecision(show: true, escalationLevel: 1, playSound: false,
                                     text: "you drifted off the deck.")

        vm.apply(decision)

        XCTAssertEqual(vm.bubbleText, "you drifted off the deck.", "a nudge still shows its bubble")
        XCTAssertFalse(vm.introActive, "a nudge must never turn the intro on (no dismiss × on nudges)")
    }
}
