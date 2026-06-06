import Foundation

/// Pure aggregation of judged `ActivitySegment`s into the day/week/month/year
/// insights that power the data-bank views and feed the coach's context.
///
/// Everything here is a deterministic function of its inputs — no database, no
/// clock, no I/O — so it is exhaustively unit-testable on fixtures. Callers
/// (the view models, the coach) fetch the relevant `ActivitySegment`,
/// `PlannedBlock` and `Goal` rows and hand them in.
struct InsightAggregator {
    /// Label used when a segment has no `category`.
    static let uncategorized = "uncategorized"

    /// Fraction of a planned block's minutes that must be spent on-task for the
    /// block to count as "fulfilled". Below this it is a miss. Tunable so tests
    /// can pin the boundary.
    var fulfilmentThreshold: Double
    /// Minimum number of times an intention must recur before a repeated miss
    /// is reported as a recurring failure pattern.
    var recurrenceThreshold: Int

    init(fulfilmentThreshold: Double = 0.5, recurrenceThreshold: Int = 2) {
        self.fulfilmentThreshold = fulfilmentThreshold
        self.recurrenceThreshold = recurrenceThreshold
    }

    // MARK: - Output types

    /// Minutes attributed to a single top-level category.
    struct CategoryMinutes: Equatable {
        var category: String
        var minutes: Double
    }

    /// On-task vs off-task vs unjudged split of time, in minutes.
    struct OnTaskSplit: Equatable {
        var onTask: Double = 0
        var offTask: Double = 0
        var unknown: Double = 0

        var total: Double { onTask + offTask + unknown }
    }

    /// Plan-vs-reality for one planned block: how long it was scheduled for and
    /// what actually happened in the segments attributed to it.
    struct BlockOutcome: Equatable {
        var blockId: String
        var title: String
        var category: String?
        var goalId: String?
        var plannedMinutes: Double
        var actualMinutes: Double
        var onTaskMinutes: Double
        var status: BlockStatus

        /// On-task minutes as a fraction of the planned minutes (0 if nothing
        /// was planned). Clamped at 1.0 is intentionally *not* applied — an
        /// over-run reads as >1 which is meaningful.
        var fulfilment: Double {
            plannedMinutes > 0 ? onTaskMinutes / plannedMinutes : 0
        }
    }

    /// A recurring intention that keeps getting planned and missed.
    struct RecurringFailure: Equatable {
        /// Human-readable intention (the first-seen planned-block title for the
        /// group; matching is case/whitespace-insensitive).
        var intention: String
        var plannedCount: Int
        var missedCount: Int
    }

    /// How a goal fared: the planned + actual time of the blocks linked to it.
    struct GoalOutcome: Equatable {
        var goalId: String
        var title: String
        var period: GoalPeriod
        var target: String?
        var plannedMinutes: Double
        var actualOnTaskMinutes: Double
        /// Whether any meaningful on-task time was logged against the goal.
        var hasProgress: Bool { actualOnTaskMinutes > 0 }
    }

    /// A single day: plan-vs-reality per block plus the category breakdown.
    struct DayInsight: Equatable {
        var totalMinutes: Double
        var split: OnTaskSplit
        var categories: [CategoryMinutes]
        var blocks: [BlockOutcome]
    }

    /// Week / month / year: zoom-out totals, leaks, goal outcomes, patterns.
    struct PeriodInsight: Equatable {
        var totalMinutes: Double
        var split: OnTaskSplit
        var categories: [CategoryMinutes]
        /// Categories where off-task time accumulates, biggest first — "where
        /// you keep leaking time".
        var timeLeaks: [CategoryMinutes]
        var goals: [GoalOutcome]
        var recurringFailures: [RecurringFailure]
    }

    // MARK: - Day

    /// Builds the day insight from the segments and the blocks planned for that
    /// day. Segments are matched to blocks by `plannedBlockId`.
    func dayInsight(segments: [ActivitySegment], blocks: [PlannedBlock]) -> DayInsight {
        DayInsight(
            totalMinutes: totalMinutes(segments),
            split: onTaskSplit(segments),
            categories: categoryBreakdown(segments),
            blocks: blockOutcomes(segments: segments, blocks: blocks)
        )
    }

    // MARK: - Period (week / month / year)

    /// Builds a multi-day insight. The period kind (week/month/year) is only a
    /// label for the caller — the aggregation is identical; the caller decides
    /// which segments/blocks/goals fall in the window.
    func periodInsight(
        segments: [ActivitySegment],
        blocks: [PlannedBlock],
        goals: [Goal]
    ) -> PeriodInsight {
        PeriodInsight(
            totalMinutes: totalMinutes(segments),
            split: onTaskSplit(segments),
            categories: categoryBreakdown(segments),
            timeLeaks: timeLeaks(segments),
            goals: goalOutcomes(segments: segments, blocks: blocks, goals: goals),
            recurringFailures: recurringFailures(segments: segments, blocks: blocks)
        )
    }

    // MARK: - Building blocks (each independently testable)

    func totalMinutes(_ segments: [ActivitySegment]) -> Double {
        segments.reduce(0) { $0 + $1.minutes }
    }

    func onTaskSplit(_ segments: [ActivitySegment]) -> OnTaskSplit {
        var split = OnTaskSplit()
        for segment in segments {
            switch segment.onTask {
            case .some(true): split.onTask += segment.minutes
            case .some(false): split.offTask += segment.minutes
            case nil: split.unknown += segment.minutes
            }
        }
        return split
    }

    /// Minutes per top-level category, biggest first. Ties break alphabetically
    /// so the ordering is deterministic.
    func categoryBreakdown(_ segments: [ActivitySegment]) -> [CategoryMinutes] {
        var totals: [String: Double] = [:]
        for segment in segments {
            let key = segment.category ?? Self.uncategorized
            totals[key, default: 0] += segment.minutes
        }
        return sortedCategoryMinutes(totals)
    }

    /// Off-task minutes per category, biggest first — the places time leaks.
    /// Categories with no off-task time are omitted.
    func timeLeaks(_ segments: [ActivitySegment]) -> [CategoryMinutes] {
        var totals: [String: Double] = [:]
        for segment in segments where segment.onTask == false {
            let key = segment.category ?? Self.uncategorized
            totals[key, default: 0] += segment.minutes
        }
        return sortedCategoryMinutes(totals)
    }

    /// Plan-vs-reality for each planned block, in the order the blocks were
    /// given (callers typically pass them sorted by start time).
    func blockOutcomes(segments: [ActivitySegment], blocks: [PlannedBlock]) -> [BlockOutcome] {
        var byBlock: [String: [ActivitySegment]] = [:]
        for segment in segments {
            guard let blockId = segment.plannedBlockId else { continue }
            byBlock[blockId, default: []].append(segment)
        }
        return blocks.map { block in
            let attributed = byBlock[block.id] ?? []
            let actual = attributed.reduce(0) { $0 + $1.minutes }
            let onTask = attributed.reduce(0) { $0 + ($1.onTask == true ? $1.minutes : 0) }
            return BlockOutcome(
                blockId: block.id,
                title: block.title,
                category: block.category,
                goalId: block.goalId,
                plannedMinutes: plannedMinutes(block),
                actualMinutes: actual,
                onTaskMinutes: onTask,
                status: block.status
            )
        }
    }

    /// Detects intentions that recur and keep getting missed ("you keep planning
    /// to email manufacturers and keep not doing it"). A block is missed if its
    /// status is `.missed` or it failed to clear the fulfilment threshold.
    func recurringFailures(segments: [ActivitySegment], blocks: [PlannedBlock]) -> [RecurringFailure] {
        let outcomes = blockOutcomes(segments: segments, blocks: blocks)
        var planned: [String: Int] = [:]
        var missed: [String: Int] = [:]
        var displayKey: [String: String] = [:]

        for outcome in outcomes {
            let key = normalizedIntention(outcome.title)
            guard !key.isEmpty else { continue }
            displayKey[key] = displayKey[key] ?? outcome.title
            planned[key, default: 0] += 1
            if isMiss(outcome) {
                missed[key, default: 0] += 1
            }
        }

        return planned.compactMap { key, plannedCount -> RecurringFailure? in
            let missedCount = missed[key] ?? 0
            guard plannedCount >= recurrenceThreshold, missedCount >= recurrenceThreshold else {
                return nil
            }
            return RecurringFailure(
                intention: displayKey[key] ?? key,
                plannedCount: plannedCount,
                missedCount: missedCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.missedCount != rhs.missedCount { return lhs.missedCount > rhs.missedCount }
            return lhs.intention < rhs.intention
        }
    }

    /// Rolls each goal up from the blocks linked to it (`PlannedBlock.goalId`)
    /// and the segments attributed to those blocks.
    func goalOutcomes(segments: [ActivitySegment], blocks: [PlannedBlock], goals: [Goal]) -> [GoalOutcome] {
        let outcomes = blockOutcomes(segments: segments, blocks: blocks)
        var plannedByGoal: [String: Double] = [:]
        var onTaskByGoal: [String: Double] = [:]
        for outcome in outcomes {
            guard let goalId = outcome.goalId else { continue }
            plannedByGoal[goalId, default: 0] += outcome.plannedMinutes
            onTaskByGoal[goalId, default: 0] += outcome.onTaskMinutes
        }
        return goals.map { goal in
            GoalOutcome(
                goalId: goal.id,
                title: goal.title,
                period: goal.period,
                target: goal.target,
                plannedMinutes: plannedByGoal[goal.id] ?? 0,
                actualOnTaskMinutes: onTaskByGoal[goal.id] ?? 0
            )
        }
    }

    // MARK: - Helpers

    private func plannedMinutes(_ block: PlannedBlock) -> Double {
        max(0, block.endAt.timeIntervalSince(block.startAt) / 60)
    }

    private func isMiss(_ outcome: BlockOutcome) -> Bool {
        if outcome.status == .missed { return true }
        // An explicitly-done block is never a miss.
        if outcome.status == .done { return false }
        guard outcome.plannedMinutes > 0 else { return false }
        return outcome.fulfilment < fulfilmentThreshold
    }

    private func normalizedIntention(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sortedCategoryMinutes(_ totals: [String: Double]) -> [CategoryMinutes] {
        totals
            .map { CategoryMinutes(category: $0.key, minutes: $0.value) }
            .sorted { lhs, rhs in
                if lhs.minutes != rhs.minutes { return lhs.minutes > rhs.minutes }
                return lhs.category < rhs.category
            }
    }
}
