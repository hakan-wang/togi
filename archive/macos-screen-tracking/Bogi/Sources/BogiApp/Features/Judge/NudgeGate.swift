import Foundation

/// Cheap, deterministic pre-check run every 5-minute tick. Only when it opens do we pay for
/// an agent invocation to decide and word a nudge. Keeps the background path cheap.
struct NudgeGate {
    let offTaskMinutesThreshold: Double

    init(offTaskMinutesThreshold: Double = 3) {
        self.offTaskMinutesThreshold = offTaskMinutesThreshold
    }

    func shouldConsiderNudge(segments: [JudgeSegment], hasActivePlan: Bool) -> Bool {
        guard hasActivePlan else { return false }
        let offTask = segments.filter { $0.onTask == false }.reduce(0) { $0 + $1.minutes }
        return offTask > offTaskMinutesThreshold
    }
}
