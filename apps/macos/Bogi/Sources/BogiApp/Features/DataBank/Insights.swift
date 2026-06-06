import Foundation

/// Shared insight value types for the data bank. These names are part of a contract
/// consumed by the dashboard views — keep them stable.

/// Total time spent in one category over a period, split out by on-task minutes.
struct CategoryTotal: Equatable {
    let category: String
    let minutes: Double
    let onTaskMinutes: Double
}

/// Plan-vs-reality for a single planned block: how long it was scheduled for versus
/// how the time actually shook out (on-task vs off-task) against that block.
struct BlockComparison: Equatable {
    let blockTitle: String
    let plannedMinutes: Double
    let onTaskMinutes: Double
    let offTaskMinutes: Double
}

/// An aggregated view of one period (day/week/month/year) of the data bank.
struct PeriodInsight: Equatable {
    let label: String           // "2026-06-06" (day) | "2026-W23" (week) | "2026-06" (month) | "2026" (year)
    let totalMinutes: Double
    let onTaskMinutes: Double
    let categories: [CategoryTotal]   // sorted desc by minutes
    let blocks: [BlockComparison]     // plan-vs-reality (populated for day; may be empty otherwise)
}

/// The selectable granularity for the dashboard.
enum DashboardPeriod {
    case day, week, month, year
}
