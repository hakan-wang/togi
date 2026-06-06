import Foundation

/// A single reminder that should be shown to the user now, ahead of a planned block/meeting.
/// Pure value type so the decision logic can be asserted directly in tests.
struct MeetingReminder: Equatable {
    let blockId: String
    let title: String
    /// Whole minutes until the block actually starts (for the message), at least 1.
    let minutesUntil: Int
    /// Which threshold (minutes-before) triggered this reminder: 30, 15, or 5.
    let offset: Int
}

/// Pure, testable decision logic for pre-meeting reminders. No SwiftUI / AppKit imports.
///
/// Design: each planned block fires at most one reminder per offset (30 / 15 / 5 min before
/// start). On every tick we compute, for each upcoming block, the *most urgent* threshold that
/// has been reached (the smallest offset whose minutes-before window the block has entered) and
/// fire it once. Larger, now-moot thresholds are marked fired too, so a block scheduled only 12
/// minutes out gets the 15-min reminder (not a stale 30-min one) and later the 5-min one.
enum MeetingReminderPlanner {
    /// Minutes-before-start thresholds, loudest/last wins.
    static let defaultOffsets = [30, 15, 5]

    /// Decide which reminders are due right now. `fired` tracks already-sent (block, offset)
    /// pairs across ticks and is updated in place. Only `planned` blocks that start in the
    /// future are considered.
    static func due(
        blocks: [PlannedBlock],
        now: Date,
        fired: inout Set<String>,
        offsets: [Int] = defaultOffsets
    ) -> [MeetingReminder] {
        let sorted = offsets.sorted(by: >)   // [30, 15, 5]
        var out: [MeetingReminder] = []
        for block in blocks {
            guard block.status == PlannerService.statusPlanned else { continue }
            let secondsUntil = block.startAt.timeIntervalSince(now)
            guard secondsUntil > 0 else { continue }              // already started / past
            let minutesUntil = secondsUntil / 60.0
            // Smallest offset whose window the block has entered = most urgent reminder due.
            guard let triggered = sorted.last(where: { Double($0) >= minutesUntil }) else { continue }
            let key = "\(block.id)#\(triggered)"
            if fired.contains(key) { continue }
            // Mark this and every larger (now-moot) threshold as fired for this block.
            for offset in sorted where offset >= triggered { fired.insert("\(block.id)#\(offset)") }
            out.append(MeetingReminder(
                blockId: block.id,
                title: block.title,
                minutesUntil: max(1, Int(minutesUntil.rounded())),
                offset: triggered
            ))
        }
        return out
    }
}
