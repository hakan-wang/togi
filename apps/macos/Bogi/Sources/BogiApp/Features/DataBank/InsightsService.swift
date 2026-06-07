import Foundation
import GRDB

/// Aggregates categorized `activity_segments` (and, for the day, `planned_blocks`) into
/// `PeriodInsight` rollups for the dashboard. All aggregation is pure and synchronous so it
/// stays testable; the database is only used to fetch the raw rows.
final class InsightsService {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    /// Build the insight for the given period containing `date`.
    func insight(for period: DashboardPeriod,
                 containing date: Date,
                 calendar: Calendar = .current) -> PeriodInsight {
        let range = Self.range(for: period, containing: date, calendar: calendar)
        let segments = fetchSegments(overlapping: range)

        let label = Self.label(for: period, containing: date, calendar: calendar)

        let totalMinutes = segments.reduce(0) { $0 + $1.minutes }
        let onTaskMinutes = segments.filter { $0.onTask == true }.reduce(0) { $0 + $1.minutes }
        let categories = Self.categoryTotals(segments)

        let blocks: [BlockComparison]
        if case .day = period {
            let plannedBlocks = fetchBlocks(overlapping: range)
            blocks = Self.blockComparisons(blocks: plannedBlocks, segments: segments)
        } else {
            blocks = []
        }

        return PeriodInsight(
            label: label,
            totalMinutes: totalMinutes,
            onTaskMinutes: onTaskMinutes,
            categories: categories,
            blocks: blocks
        )
    }

    // MARK: - Pure aggregation

    /// Group segments by `category ?? "uncategorized"`, summing minutes + on-task minutes.
    /// Sorted descending by total minutes (ties broken by category name for determinism).
    static func categoryTotals(_ segments: [ActivitySegment]) -> [CategoryTotal] {
        var minutesByCategory: [String: Double] = [:]
        var onTaskByCategory: [String: Double] = [:]
        for seg in segments {
            let key = seg.cat ?? "uncategorized"
            minutesByCategory[key, default: 0] += seg.minutes
            if seg.onTask == true {
                onTaskByCategory[key, default: 0] += seg.minutes
            }
        }
        return minutesByCategory
            .map { CategoryTotal(category: $0.key, minutes: $0.value, onTaskMinutes: onTaskByCategory[$0.key] ?? 0) }
            .sorted { ($0.minutes, $1.category) > ($1.minutes, $0.category) }
    }

    /// Build plan-vs-reality comparisons for each planned block. On/off-task minutes come from
    /// segments whose `plannedBlockId` matches the block id.
    static func blockComparisons(blocks: [PlannedBlock], segments: [ActivitySegment]) -> [BlockComparison] {
        var byBlock: [String: [ActivitySegment]] = [:]
        for seg in segments {
            guard let bid = seg.plannedBlockId else { continue }
            byBlock[bid, default: []].append(seg)
        }
        return blocks.map { block in
            let segs = byBlock[block.id] ?? []
            let onTask = segs.filter { $0.onTask == true }.reduce(0) { $0 + $1.minutes }
            let offTask = segs.filter { $0.onTask == false }.reduce(0) { $0 + $1.minutes }
            let planned = block.endAt.timeIntervalSince(block.startAt) / 60.0
            return BlockComparison(
                blockTitle: block.title,
                plannedMinutes: planned,
                onTaskMinutes: onTask,
                offTaskMinutes: offTask
            )
        }
    }

    // MARK: - Period math

    /// [start, end) interval for the period containing `date`.
    static func range(for period: DashboardPeriod,
                      containing date: Date,
                      calendar: Calendar = .current) -> Range<Date> {
        let component: Calendar.Component
        switch period {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        let interval = calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date),
                            end: calendar.startOfDay(for: date).addingTimeInterval(86_400))
        return interval.start..<interval.end
    }

    /// Contract-formatted label for the period.
    static func label(for period: DashboardPeriod,
                      containing date: Date,
                      calendar: Calendar = .current) -> String {
        var calendar = calendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone

        switch period {
        case .day:
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        case .week:
            let year = calendar.component(.yearForWeekOfYear, from: date)
            let week = calendar.component(.weekOfYear, from: date)
            return String(format: "%04d-W%02d", year, week)
        case .month:
            formatter.dateFormat = "yyyy-MM"
            return formatter.string(from: date)
        case .year:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        }
    }

    // MARK: - Fetching

    private func fetchSegments(overlapping range: Range<Date>) -> [ActivitySegment] {
        (try? database.dbQueue.read { db in
            // Overlap: segment starts before range end AND ends after range start.
            try ActivitySegment
                .filter(Column("start_at") < range.upperBound && Column("end_at") > range.lowerBound)
                .order(Column("start_at"))
                .fetchAll(db)
        }) ?? []
    }

    private func fetchBlocks(overlapping range: Range<Date>) -> [PlannedBlock] {
        (try? database.dbQueue.read { db in
            try PlannedBlock
                .filter(Column("start_at") < range.upperBound && Column("end_at") > range.lowerBound)
                .order(Column("start_at"))
                .fetchAll(db)
        }) ?? []
    }
}
