import XCTest
import GRDB
@testable import BogiApp

@MainActor
final class MascotTests: XCTestCase {

    // MARK: - MascotState mood mapping

    func testMoodSpeakingWinsOverEverything() {
        // Speaking always wins, regardless of activity / on-task signal.
        XCTAssertEqual(MascotState.mood(for: MascotInput(isSpeaking: true, isActive: false, onTask: nil)), .speaking)
        XCTAssertEqual(MascotState.mood(for: MascotInput(isSpeaking: true, isActive: true, onTask: true)), .speaking)
        XCTAssertEqual(MascotState.mood(for: MascotInput(isSpeaking: true, isActive: true, onTask: false)), .speaking)
    }

    func testMoodIdleWhenInactiveOrUnknown() {
        XCTAssertEqual(MascotState.mood(for: .unknown), .idle)
        // Inactive but with a known signal → still idle (no recent activity).
        XCTAssertEqual(MascotState.mood(for: MascotInput(isSpeaking: false, isActive: false, onTask: true)), .idle)
        // Active but no known on/off-task signal → idle.
        XCTAssertEqual(MascotState.mood(for: MascotInput(isSpeaking: false, isActive: true, onTask: nil)), .idle)
    }

    func testMoodOnVsOffTaskWhenActive() {
        XCTAssertEqual(MascotState.mood(for: MascotInput(isSpeaking: false, isActive: true, onTask: true)), .onTask)
        XCTAssertEqual(MascotState.mood(for: MascotInput(isSpeaking: false, isActive: true, onTask: false)), .offTask)
    }

    // MARK: - NudgePolicy escalation timing

    func testSeverityStaysCalmBeforeThreshold() {
        let policy = NudgePolicy(config: .standard) // N = 3, max = 6
        for ticks in 0..<3 {
            XCTAssertEqual(policy.severity(forIgnoredTicks: ticks), .calm, "ticks=\(ticks)")
        }
    }

    func testSeverityEscalatesAtAndAfterThreshold() {
        let policy = NudgePolicy(config: .standard)
        XCTAssertEqual(policy.severity(forIgnoredTicks: 3), .firm)
        XCTAssertEqual(policy.severity(forIgnoredTicks: 5), .firm)
        XCTAssertEqual(policy.severity(forIgnoredTicks: 6), .loud)
        XCTAssertEqual(policy.severity(forIgnoredTicks: 99), .loud)
    }

    func testNoSoundBeforeThresholdSoundAndSizeAfter() {
        let policy = NudgePolicy(config: .standard)
        let now = Date()

        // Before N: shown, calm, no sound, baseline size.
        for ticks in 0..<3 {
            let d = policy.decide(NudgeContext(ignoredTicks: ticks, now: now))
            XCTAssertTrue(d.show)
            XCTAssertEqual(d.severity, .calm)
            XCTAssertFalse(d.playSound, "no sound before N (ticks=\(ticks))")
            XCTAssertEqual(d.scale, 1.0, accuracy: 0.0001)
        }

        // At/after N: shown, escalated, sound on, larger.
        let firm = policy.decide(NudgeContext(ignoredTicks: 3, now: now))
        XCTAssertTrue(firm.show)
        XCTAssertEqual(firm.severity, .firm)
        XCTAssertTrue(firm.playSound, "sound after N")
        XCTAssertGreaterThan(firm.scale, 1.0)

        let loud = policy.decide(NudgeContext(ignoredTicks: 6, now: now))
        XCTAssertEqual(loud.severity, .loud)
        XCTAssertTrue(loud.playSound)
        XCTAssertGreaterThan(loud.scale, firm.scale)
    }

    // MARK: - NudgePolicy suppression

    func testSnoozeSuppresses() {
        let policy = NudgePolicy(config: .standard)
        let now = Date()
        let snoozed = SnoozeState(until: now.addingTimeInterval(300))
        let d = policy.decide(NudgeContext(ignoredTicks: 5, now: now, snooze: snoozed))
        XCTAssertFalse(d.show)
        XCTAssertEqual(d.suppression, .snoozed)
        XCTAssertFalse(d.playSound)
    }

    func testSnoozeExpiresAllowsNudge() {
        let policy = NudgePolicy(config: .standard)
        let now = Date()
        // Snooze already in the past → not suppressed.
        let expired = SnoozeState(until: now.addingTimeInterval(-1))
        let d = policy.decide(NudgeContext(ignoredTicks: 0, now: now, snooze: expired))
        XCTAssertTrue(d.show)
        XCTAssertNil(d.suppression)
    }

    func testDNDWindowSuppresses() {
        let policy = NudgePolicy(config: .standard)
        let now = Date()
        let window = DNDWindow(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))
        let d = policy.decide(NudgeContext(ignoredTicks: 9, now: now, dndWindows: [window]))
        XCTAssertFalse(d.show)
        XCTAssertEqual(d.suppression, .dnd)
    }

    func testDNDWindowOutsideDoesNotSuppress() {
        let policy = NudgePolicy(config: .standard)
        let now = Date()
        // Window already ended (half-open end is exclusive, so `now` is outside).
        let past = DNDWindow(start: now.addingTimeInterval(-120), end: now)
        let d = policy.decide(NudgeContext(ignoredTicks: 0, now: now, dndWindows: [past]))
        XCTAssertTrue(d.show)
        XCTAssertNil(d.suppression)
    }

    func testGlobalDNDSuppresses() {
        let policy = NudgePolicy(config: .standard)
        let now = Date()
        let d = policy.decide(NudgeContext(ignoredTicks: 9, now: now, globalDND: true))
        XCTAssertFalse(d.show)
        XCTAssertEqual(d.suppression, .dnd)
    }

    func testDNDTakesPrecedenceOverSnooze() {
        let policy = NudgePolicy(config: .standard)
        let now = Date()
        let snoozed = SnoozeState(until: now.addingTimeInterval(300))
        let d = policy.decide(NudgeContext(ignoredTicks: 0, now: now, snooze: snoozed, globalDND: true))
        XCTAssertFalse(d.show)
        XCTAssertEqual(d.suppression, .dnd)
    }

    // MARK: - NudgePresenter outcomes

    func testPresenterMarksShownAndDismiss() {
        let env = makePresenter()
        env.presenter.present(makeNudge(id: "n1"))

        XCTAssertEqual(env.bubble.shown.count, 1)
        XCTAssertEqual(env.outcomes.shown["n1"], true)
        XCTAssertEqual(env.presenter.lastDecision?.severity, .calm)

        env.presenter.dismiss()
        XCTAssertEqual(env.outcomes.outcomes["n1"], .dismissed)
        XCTAssertTrue(env.bubble.hidden) // bubble hidden after resolution
        XCTAssertNil(env.presenter.activeNudge)
        XCTAssertEqual(env.presenter.ignoredTicks, 0)
    }

    func testPresenterHeeded() {
        let env = makePresenter()
        env.presenter.present(makeNudge(id: "n1"))
        env.presenter.heeded()
        XCTAssertEqual(env.outcomes.outcomes["n1"], .heeded)
    }

    func testPresenterSnoozeRecordsOutcomeAndSuppressesNext() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let env = makePresenter(clock: { clock })
        env.presenter.present(makeNudge(id: "n1"))
        env.presenter.snoozeCurrent(for: 600)
        XCTAssertEqual(env.outcomes.outcomes["n1"], .snoozed)

        // A nudge arriving while snoozed is suppressed (not shown).
        let shownBefore = env.bubble.shown.count
        clock = clock.addingTimeInterval(60) // still within the 600s snooze
        env.presenter.present(makeNudge(id: "n2"))
        XCTAssertEqual(env.bubble.shown.count, shownBefore, "snoozed nudge must not be shown")
        XCTAssertEqual(env.presenter.lastDecision?.suppression, .snoozed)
        XCTAssertNil(env.outcomes.outcomes["n2"], "suppressed nudge writes no outcome")

        // After the snooze expires, nudges show again.
        clock = clock.addingTimeInterval(600)
        env.presenter.present(makeNudge(id: "n3"))
        XCTAssertEqual(env.outcomes.shown["n3"], true)
    }

    func testPresenterEscalatesAfterIgnoredTicksAndRecordsEscalated() {
        let env = makePresenter() // standard config: escalate at 3 ignored
        // Present the same drift repeatedly without resolving.
        // ignoredTicks at decision time: 0,1,2 (calm), then 3 (escalates).
        env.presenter.present(makeNudge(id: "a"))
        env.presenter.present(makeNudge(id: "b"))
        env.presenter.present(makeNudge(id: "c"))
        XCTAssertEqual(env.presenter.lastDecision?.severity, .calm)
        XCTAssertFalse(env.presenter.lastDecision?.playSound ?? true)

        env.presenter.present(makeNudge(id: "d")) // 4th: ignoredTicks==3 → firm
        XCTAssertEqual(env.presenter.lastDecision?.severity, .firm)
        XCTAssertTrue(env.presenter.lastDecision?.playSound ?? false)
        XCTAssertEqual(env.outcomes.outcomes["d"], .escalated, "escalation is recorded as the outcome")
    }

    func testPresenterDNDSuppressesPresentation() {
        let env = makePresenter(globalDND: { true })
        env.presenter.present(makeNudge(id: "n1"))
        XCTAssertTrue(env.bubble.shown.isEmpty)
        XCTAssertEqual(env.presenter.lastDecision?.suppression, .dnd)
        XCTAssertNil(env.outcomes.outcomes["n1"])
    }

    func testPresenterOpenCoachMarksHeededAndCallsCoach() {
        let env = makePresenter()
        env.presenter.present(makeNudge(id: "n1"))
        let anchor = MascotAnchor(x: 1, y: 2, width: 3, height: 4)
        env.presenter.openCoach(anchoredTo: anchor, prompt: "hi")
        XCTAssertEqual(env.outcomes.outcomes["n1"], .heeded)
        XCTAssertEqual(env.coach.calls.count, 1)
        XCTAssertEqual(env.coach.calls.first?.anchor, anchor)
        XCTAssertEqual(env.coach.calls.first?.prompt, "hi")
    }

    // MARK: - DatabaseNudgeOutcomeStore (real GRDB)

    func testDatabaseOutcomeStoreWritesShownAndOutcome() throws {
        let service = try DatabaseService(inMemory: true)
        try service.dbQueue.write { db in
            var n = Nudge(id: "n1", segmentId: nil, plannedBlockId: nil, severity: 1, message: "back to it", shownAt: nil, outcome: nil)
            try n.insert(db)
        }
        let store = DatabaseNudgeOutcomeStore(database: service)
        let when = Date(timeIntervalSince1970: 5_000)
        store.markShown(nudgeId: "n1", at: when)
        store.record(nudgeId: "n1", outcome: .heeded)

        let loaded = try service.dbQueue.read { db in try Nudge.fetchOne(db, key: "n1") }
        XCTAssertEqual(loaded?.outcome, .heeded)
        XCTAssertEqual(loaded?.shownAt?.timeIntervalSince1970 ?? 0, 5_000, accuracy: 1.0)
    }

    func testDatabaseOutcomeStoreMarkShownIsIdempotent() throws {
        let service = try DatabaseService(inMemory: true)
        try service.dbQueue.write { db in
            var n = Nudge(id: "n1", segmentId: nil, plannedBlockId: nil, severity: 0, message: "hi", shownAt: nil, outcome: nil)
            try n.insert(db)
        }
        let store = DatabaseNudgeOutcomeStore(database: service)
        let first = Date(timeIntervalSince1970: 1_000)
        store.markShown(nudgeId: "n1", at: first)
        store.markShown(nudgeId: "n1", at: first.addingTimeInterval(999)) // ignored

        let loaded = try service.dbQueue.read { db in try Nudge.fetchOne(db, key: "n1") }
        XCTAssertEqual(loaded?.shownAt?.timeIntervalSince1970 ?? 0, 1_000, accuracy: 1.0)
    }

    // MARK: - Helpers

    private func makeNudge(id: String, message: String = "back to the timeline") -> Nudge {
        Nudge(id: id, segmentId: nil, plannedBlockId: nil, severity: 0, message: message, shownAt: nil, outcome: nil)
    }

    private struct PresenterEnv {
        let presenter: NudgePresenter
        let bubble: SpyBubble
        let outcomes: SpyOutcomes
        let coach: SpyCoach
    }

    private func makePresenter(
        config: NudgePolicyConfig = .standard,
        globalDND: @escaping () -> Bool = { false },
        dndWindows: @escaping () -> [DNDWindow] = { [] },
        clock: @escaping () -> Date = Date.init
    ) -> PresenterEnv {
        let bubble = SpyBubble()
        let outcomes = SpyOutcomes()
        let coach = SpyCoach()
        let presenter = NudgePresenter(
            policy: NudgePolicy(config: config),
            bubble: bubble,
            outcomes: outcomes,
            coach: coach,
            dndWindowsProvider: dndWindows,
            globalDNDProvider: globalDND,
            clock: clock
        )
        return PresenterEnv(presenter: presenter, bubble: bubble, outcomes: outcomes, coach: coach)
    }
}

// MARK: - Test doubles

private final class SpyBubble: NudgeBubblePresenting {
    var shown: [(message: String, decision: NudgeDecision)] = []
    var hidden = false
    func showBubble(message: String, decision: NudgeDecision) {
        shown.append((message, decision))
        hidden = false
    }
    func hideBubble() { hidden = true }
}

private final class SpyOutcomes: NudgeOutcomeStore {
    var shown: [String: Bool] = [:]
    var outcomes: [String: NudgeOutcome] = [:]
    func markShown(nudgeId: String, at: Date) { shown[nudgeId] = true }
    func record(nudgeId: String, outcome: NudgeOutcome) { outcomes[nudgeId] = outcome }
}

private final class SpyCoach: CoachPresenting {
    var calls: [(anchor: MascotAnchor, prompt: String?)] = []
    func presentCoach(anchoredTo anchor: MascotAnchor, prompt: String?) {
        calls.append((anchor, prompt))
    }
}
