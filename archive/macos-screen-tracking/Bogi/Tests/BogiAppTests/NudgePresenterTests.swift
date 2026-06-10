import XCTest
@testable import BogiApp

final class NudgePresenterTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testCalmFirstNudge() {
        let presenter = NudgePresenter()
        let d = presenter.present(message: "Back to the deck.", now: t0)
        XCTAssertTrue(d.show)
        XCTAssertEqual(d.escalationLevel, 0)
        XCTAssertFalse(d.playSound)
        XCTAssertEqual(d.text, "Back to the deck.")
    }

    func testEscalationRisesOnRepeatedWithinWindow() {
        let presenter = NudgePresenter(escalationWindow: 90, maxEscalation: 3, soundThreshold: 2)

        let d0 = presenter.present(message: "Still off-task.", now: at(0))
        XCTAssertEqual(d0.escalationLevel, 0)
        XCTAssertFalse(d0.playSound)

        let d1 = presenter.present(message: "Still off-task.", now: at(30))
        XCTAssertEqual(d1.escalationLevel, 1)
        XCTAssertFalse(d1.playSound)

        // Level 2 → sound kicks in.
        let d2 = presenter.present(message: "Still off-task.", now: at(60))
        XCTAssertEqual(d2.escalationLevel, 2)
        XCTAssertTrue(d2.playSound)

        // Level 3 → capped, still sounding.
        let d3 = presenter.present(message: "Still off-task.", now: at(90))
        XCTAssertEqual(d3.escalationLevel, 3)
        XCTAssertTrue(d3.playSound)

        // Stays capped at max.
        let d4 = presenter.present(message: "Still off-task.", now: at(120))
        XCTAssertEqual(d4.escalationLevel, 3)
        XCTAssertTrue(d4.playSound)
    }

    func testNudgeOutsideWindowResetsToCalm() {
        let presenter = NudgePresenter(escalationWindow: 90)
        _ = presenter.present(message: "x", now: at(0))
        let d1 = presenter.present(message: "x", now: at(30))
        XCTAssertEqual(d1.escalationLevel, 1)

        // Gap longer than the window → fresh, calm nudge.
        let d2 = presenter.present(message: "x", now: at(30 + 200))
        XCTAssertEqual(d2.escalationLevel, 0)
        XCTAssertFalse(d2.playSound)
    }

    func testSnoozeSuppressesUntilExpiry() {
        let presenter = NudgePresenter()
        presenter.snooze(minutes: 10, now: t0)

        // During snooze → suppressed.
        let suppressed = presenter.present(message: "x", now: at(60))
        XCTAssertFalse(suppressed.show)
        XCTAssertNil(suppressed.text)
        XCTAssertFalse(suppressed.playSound)

        // Still suppressed just before expiry.
        XCTAssertFalse(presenter.present(message: "x", now: at(10 * 60 - 1)).show)

        // After expiry → shows again, calm.
        let after = presenter.present(message: "x", now: at(10 * 60 + 1))
        XCTAssertTrue(after.show)
        XCTAssertEqual(after.escalationLevel, 0)
    }

    func testDNDSuppresses() {
        let presenter = NudgePresenter()
        presenter.setDND(until: at(3600))

        XCTAssertFalse(presenter.present(message: "x", now: at(60)).show)
        XCTAssertFalse(presenter.present(message: "x", now: at(3599)).show)

        // After DND ends → shows.
        XCTAssertTrue(presenter.present(message: "x", now: at(3601)).show)
    }

    func testClearDNDLiftsSuppression() {
        let presenter = NudgePresenter()
        presenter.setDND(until: at(3600))
        XCTAssertFalse(presenter.present(message: "x", now: at(60)).show)

        presenter.clearDND()
        XCTAssertTrue(presenter.present(message: "x", now: at(120)).show)
    }

    func testAcknowledgeResetsEscalation() {
        let presenter = NudgePresenter(escalationWindow: 90, soundThreshold: 2)
        _ = presenter.present(message: "x", now: at(0))
        _ = presenter.present(message: "x", now: at(30))
        let escalated = presenter.present(message: "x", now: at(60))
        XCTAssertEqual(escalated.escalationLevel, 2)
        XCTAssertTrue(escalated.playSound)

        presenter.acknowledge(now: at(70))
        XCTAssertEqual(presenter.currentEscalation, 0)
        XCTAssertEqual(presenter.consecutiveIgnored, 0)

        // Next nudge — even within the old window — starts calm again.
        let fresh = presenter.present(message: "x", now: at(80))
        XCTAssertEqual(fresh.escalationLevel, 0)
        XCTAssertFalse(fresh.playSound)
    }

    func testIsSuppressedReflectsSnoozeAndDND() {
        let presenter = NudgePresenter()
        XCTAssertFalse(presenter.isSuppressed(now: t0))

        presenter.snooze(minutes: 5, now: t0)
        XCTAssertTrue(presenter.isSuppressed(now: at(60)))
        XCTAssertFalse(presenter.isSuppressed(now: at(5 * 60 + 1)))
    }
}
