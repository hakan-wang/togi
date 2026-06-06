import Foundation

/// The 5-minute heartbeat. One `runOnce` = one judge tick: build prompt → infer → parse →
/// persist segments → return the nudge decision.
///
/// Scheduling lives OUTSIDE this class: at integration a 5-min DispatchSourceTimer (mirroring
/// CaptureController.start) will gather a JudgeInput from an observation provider + the active
/// planned block and call `runOnce`, then route the returned nudge to the nudge UI.
final class JudgeService {
    private let inference: InferenceClient
    private let segmentStore: SegmentStore
    private let clock: () -> Date

    /// Token budget for the judge reply. Generous enough for a handful of segments + nudge.
    private let maxTokens = 1024

    init(inference: InferenceClient,
         segmentStore: SegmentStore,
         clock: @escaping () -> Date = { Date() }) {
        self.inference = inference
        self.segmentStore = segmentStore
        self.clock = clock
    }

    /// Run a single judge cycle. Persists the parsed segments and returns the nudge decision.
    @discardableResult
    func runOnce(input: JudgeInput) async throws -> JudgeNudge {
        let userJSON = JudgePrompt.userJSON(input)
        let raw = try await inference.infer(
            system: JudgePrompt.system,
            messages: [InferenceMessage(role: "user", content: userJSON)],
            maxTokens: maxTokens
        )

        let output = try JudgeOutput.parse(raw)
        let judgedAt = clock()

        // JudgeInput's active block carries no id, so segments persist with nil
        // planned_block_id. At integration the caller can pass the block id and link them.
        for seg in output.segments {
            let segment = ActivitySegment(
                id: UUID().uuidString,
                startAt: seg.startAt,
                endAt: seg.endAt,
                minutes: seg.minutes,
                plannedBlockId: nil,
                category: seg.category,
                subCategory: seg.subCategory,
                subSub: seg.subSub,
                onTask: seg.onTask,
                confidence: seg.confidence,
                judgedAt: judgedAt
            )
            segmentStore.insert(segment)
        }

        return output.nudge
    }
}
