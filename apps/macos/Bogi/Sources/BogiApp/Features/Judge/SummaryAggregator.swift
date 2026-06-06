import Foundation

/// Per-category time totals, split by on-/off-task.
struct CategoryTotal: Codable, Equatable {
    var category: String
    var minutes: Double
    var onTaskMinutes: Double
    var offTaskMinutes: Double

    enum CodingKeys: String, CodingKey {
        case category, minutes
        case onTaskMinutes = "on_task_minutes"
        case offTaskMinutes = "off_task_minutes"
    }
}

/// Rolled-up view of a set of `activity_segments` for a day/week/month: total
/// minutes, the on-/off-task split, plan-vs-reality (planned vs unplanned), and
/// a category breakdown. This is the JSON stored in the `*_summaries` tables.
struct ActivitySummary: Codable, Equatable {
    var totalMinutes: Double
    var onTaskMinutes: Double
    var offTaskMinutes: Double
    var plannedMinutes: Double
    var unplannedMinutes: Double
    var segmentCount: Int
    var categories: [CategoryTotal]

    enum CodingKeys: String, CodingKey {
        case categories
        case totalMinutes = "total_minutes"
        case onTaskMinutes = "on_task_minutes"
        case offTaskMinutes = "off_task_minutes"
        case plannedMinutes = "planned_minutes"
        case unplannedMinutes = "unplanned_minutes"
        case segmentCount = "segment_count"
    }
}

/// Cheap, pure aggregation of judged segments into summaries. No database or
/// clock dependency: callers pass the segments (and a calendar/time zone for the
/// bucketing keys), so every function here is deterministic and unit-testable.
enum SummaryAggregator {
    enum Granularity {
        case daily, weekly, monthly
    }

    /// Totals + category breakdown for an arbitrary set of segments. Categories
    /// are sorted by minutes descending (ties broken by name) for stable output.
    static func summarize(_ segments: [ActivitySegment]) -> ActivitySummary {
        var total = 0.0
        var onTask = 0.0
        var offTask = 0.0
        var planned = 0.0
        var unplanned = 0.0
        var byCategory: [String: (minutes: Double, on: Double, off: Double)] = [:]

        for segment in segments {
            let minutes = segment.minutes
            total += minutes

            if segment.onTask == true {
                onTask += minutes
            } else if segment.onTask == false {
                offTask += minutes
            }

            if segment.plannedBlockId != nil {
                planned += minutes
            } else {
                unplanned += minutes
            }

            let key = segment.category ?? "uncategorized"
            var bucket = byCategory[key] ?? (0, 0, 0)
            bucket.minutes += minutes
            if segment.onTask == true { bucket.on += minutes }
            if segment.onTask == false { bucket.off += minutes }
            byCategory[key] = bucket
        }

        let categories = byCategory
            .map { CategoryTotal(category: $0.key, minutes: $0.value.minutes,
                                 onTaskMinutes: $0.value.on, offTaskMinutes: $0.value.off) }
            .sorted { lhs, rhs in
                lhs.minutes == rhs.minutes ? lhs.category < rhs.category : lhs.minutes > rhs.minutes
            }

        return ActivitySummary(
            totalMinutes: total,
            onTaskMinutes: onTask,
            offTaskMinutes: offTask,
            plannedMinutes: planned,
            unplannedMinutes: unplanned,
            segmentCount: segments.count,
            categories: categories
        )
    }

    /// Buckets segments by period key (yyyy-MM-dd / yyyy-Www / yyyy-MM) and
    /// summarizes each bucket. Segments are bucketed by their `start_at`.
    static func group(
        _ segments: [ActivitySegment],
        by granularity: Granularity,
        calendar: Calendar = isoCalendar
    ) -> [String: ActivitySummary] {
        var buckets: [String: [ActivitySegment]] = [:]
        for segment in segments {
            let key = bucketKey(for: segment.startAt, granularity: granularity, calendar: calendar)
            buckets[key, default: []].append(segment)
        }
        return buckets.mapValues(summarize)
    }

    /// The period key a date falls into for the given granularity.
    static func bucketKey(
        for date: Date,
        granularity: Granularity,
        calendar: Calendar = isoCalendar
    ) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .weekOfYear, .yearForWeekOfYear],
            from: date
        )
        switch granularity {
        case .daily:
            return String(format: "%04d-%02d-%02d",
                          components.year ?? 0, components.month ?? 0, components.day ?? 0)
        case .weekly:
            return String(format: "%04d-W%02d",
                          components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
        case .monthly:
            return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        }
    }

    /// Encodes a summary to the JSON string stored in the `*_summaries` tables.
    static func json(_ summary: ActivitySummary) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(summary)
        return String(decoding: data, as: UTF8.self)
    }

    /// UTC, Monday-first ISO calendar so bucket keys are stable regardless of the
    /// machine's locale/time zone.
    static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()
}
