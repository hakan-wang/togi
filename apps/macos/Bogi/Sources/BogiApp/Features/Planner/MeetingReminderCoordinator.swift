import Foundation

/// Drives pre-meeting reminders: on a short timer it looks at planned blocks starting soon and
/// fires a reminder at the 30 / 15 / 5-minute marks. Surfacing is injected (mascot bubble, or a
/// breather offer) so this coordinator stays free of AppKit and is unit-testable via `tick(now:)`.
///
/// Reminders are gated on the `meeting_reminders` setting (default on). When `meeting_breather` is
/// on, the 5-minute mark offers a grounding breath instead of a plain bubble — linking calm to the
/// calendar.
@MainActor
final class MeetingReminderCoordinator {
    private let blocks: PlannedBlockRepository
    private let settings: SettingsStore
    private let onReminder: (MeetingReminder) -> Void
    private let onBreather: (MeetingReminder) -> Void
    private let checkInterval: TimeInterval
    /// Look slightly past the largest offset (30 min) so a block is caught before its first mark.
    private let lookahead: TimeInterval = 31 * 60

    private var fired: Set<String> = []
    private var timer: DispatchSourceTimer?

    init(
        blocks: PlannedBlockRepository,
        settings: SettingsStore,
        onReminder: @escaping (MeetingReminder) -> Void,
        onBreather: @escaping (MeetingReminder) -> Void,
        checkInterval: TimeInterval = 30
    ) {
        self.blocks = blocks
        self.settings = settings
        self.onReminder = onReminder
        self.onBreather = onBreather
        self.checkInterval = checkInterval
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 10, repeating: checkInterval)
        t.setEventHandler { [weak self] in Task { @MainActor in self?.tick() } }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// One reminder cycle. Exposed (with an injectable `now`) so tests can drive it deterministically.
    func tick(now: Date = Date()) {
        guard settings.bool("meeting_reminders", default: true) else { return }
        let upcoming = blocks.upcoming(within: lookahead, from: now)
        let due = MeetingReminderPlanner.due(blocks: upcoming, now: now, fired: &fired)
        let breatherOn = settings.bool("meeting_breather", default: false)
        for reminder in due {
            if reminder.offset <= 5, breatherOn {
                onBreather(reminder)
            } else {
                onReminder(reminder)
            }
        }
        // Keep the fired-set from growing without bound over a long-running session.
        if fired.count > 500 { fired.removeAll() }
    }
}
