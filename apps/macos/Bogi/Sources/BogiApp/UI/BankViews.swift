import SwiftUI
import GRDB

/// The data-bank dashboard: Day / Week / Month / Year zoom over the judged
/// segments. Each scope renders the same aggregates (`InsightAggregator`) over a
/// different window. Loading + aggregation lives in `BankViewModel`; the views
/// are presentation-only.

enum BankScope: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}

/// Loads the segments/blocks/goals for a scope's window and runs the pure
/// `InsightAggregator`. Holds only derived view state.
@MainActor
final class BankViewModel: ObservableObject {
    @Published var scope: BankScope = .day
    @Published var anchor: Date = Date()
    @Published var day: InsightAggregator.DayInsight?
    @Published var period: InsightAggregator.PeriodInsight?
    @Published var errorText: String?

    private let database: DatabaseService
    private let aggregator = InsightAggregator()
    private let calendar: Calendar

    init(database: DatabaseService, calendar: Calendar = .current) {
        self.database = database
        self.calendar = calendar
    }

    /// Inclusive-start, exclusive-end window for the current scope + anchor.
    func window() -> (start: Date, end: Date) {
        let start: Date
        let component: Calendar.Component
        switch scope {
        case .day: component = .day; start = calendar.startOfDay(for: anchor)
        case .week: component = .weekOfYear; start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? calendar.startOfDay(for: anchor)
        case .month: component = .month; start = calendar.dateInterval(of: .month, for: anchor)?.start ?? calendar.startOfDay(for: anchor)
        case .year: component = .year; start = calendar.dateInterval(of: .year, for: anchor)?.start ?? calendar.startOfDay(for: anchor)
        }
        let end = calendar.date(byAdding: component, value: 1, to: start) ?? start
        return (start, end)
    }

    func reload() {
        let (start, end) = window()
        do {
            let segments = try database.dbQueue.read { db in
                try ActivitySegment
                    .filter(Column("start_at") >= start && Column("start_at") < end)
                    .order(Column("start_at"))
                    .fetchAll(db)
            }
            let blocks = try database.dbQueue.read { db in
                try PlannedBlock
                    .filter(Column("start_at") >= start && Column("start_at") < end)
                    .order(Column("start_at"))
                    .fetchAll(db)
            }
            let goals = try database.dbQueue.read { db in
                try Goal.order(Column("created_at").desc).fetchAll(db)
            }
            if scope == .day {
                day = aggregator.dayInsight(segments: segments, blocks: blocks)
                period = nil
            } else {
                period = aggregator.periodInsight(segments: segments, blocks: blocks, goals: goals)
                day = nil
            }
            errorText = nil
        } catch {
            errorText = "\(error)"
        }
    }
}

struct BankView: View {
    @StateObject private var model: BankViewModel

    init(database: DatabaseService) {
        _model = StateObject(wrappedValue: BankViewModel(database: database))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Scope", selection: $model.scope) {
                ForEach(BankScope.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.scope) { _, _ in model.reload() }

            if let error = model.errorText {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            ScrollView {
                if let day = model.day {
                    DayInsightView(insight: day)
                } else if let period = model.period {
                    PeriodInsightView(insight: period)
                } else {
                    Text("No data for this period.").foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 480, minHeight: 420)
        .onAppear { model.reload() }
    }
}

// MARK: - Day

struct DayInsightView: View {
    let insight: InsightAggregator.DayInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SplitSummaryView(title: "Today", total: insight.totalMinutes, split: insight.split)

            if !insight.blocks.isEmpty {
                SectionHeader("Plan vs reality")
                ForEach(insight.blocks, id: \.blockId) { BlockOutcomeRow(outcome: $0) }
            }

            if !insight.categories.isEmpty {
                SectionHeader("Where the time went")
                CategoryListView(items: insight.categories, total: insight.totalMinutes)
            }
        }
    }
}

struct BlockOutcomeRow: View {
    let outcome: InsightAggregator.BlockOutcome

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.title).font(.body)
                Text("planned \(MinutesFormat.short(outcome.plannedMinutes)) · on-task \(MinutesFormat.short(outcome.onTaskMinutes))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int((outcome.fulfilment * 100).rounded()))%")
                .font(.headline)
                .foregroundStyle(outcome.fulfilment >= 0.5 ? Color.green : Color.orange)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Period

struct PeriodInsightView: View {
    let insight: InsightAggregator.PeriodInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SplitSummaryView(title: "Total", total: insight.totalMinutes, split: insight.split)

            if !insight.categories.isEmpty {
                SectionHeader("Category breakdown")
                CategoryListView(items: insight.categories, total: insight.totalMinutes)
            }

            if !insight.timeLeaks.isEmpty {
                SectionHeader("Where you leak time")
                CategoryListView(items: insight.timeLeaks, total: insight.split.offTask)
            }

            if !insight.goals.isEmpty {
                SectionHeader("Goals")
                ForEach(insight.goals, id: \.goalId) { GoalOutcomeRow(outcome: $0) }
            }

            if !insight.recurringFailures.isEmpty {
                SectionHeader("Recurring failures")
                ForEach(insight.recurringFailures, id: \.intention) { failure in
                    Text("You planned “\(failure.intention)” \(failure.plannedCount)× and missed it \(failure.missedCount)×.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

struct GoalOutcomeRow: View {
    let outcome: InsightAggregator.GoalOutcome

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.title)
                Text("\(outcome.period.rawValue) · on-task \(MinutesFormat.short(outcome.actualOnTaskMinutes)) of planned \(MinutesFormat.short(outcome.plannedMinutes))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: outcome.hasProgress ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(outcome.hasProgress ? Color.green : Color.red)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shared pieces

private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.headline).padding(.top, 4)
    }
}

private struct SplitSummaryView: View {
    let title: String
    let total: Double
    let split: InsightAggregator.OnTaskSplit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3).bold()
            Text("\(MinutesFormat.short(total)) tracked")
            Text("on-task \(MinutesFormat.short(split.onTask)) · off-task \(MinutesFormat.short(split.offTask)) · unjudged \(MinutesFormat.short(split.unknown))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CategoryListView: View {
    let items: [InsightAggregator.CategoryMinutes]
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.category) { item in
                HStack {
                    Text(item.category)
                    Spacer()
                    Text("\(MinutesFormat.short(item.minutes))")
                        .foregroundStyle(.secondary)
                    if total > 0 {
                        Text("\(Int((item.minutes / total * 100).rounded()))%")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Formats a minutes value as a compact "1h 5m" / "45m" string.
enum MinutesFormat {
    static func short(_ value: Double) -> String {
        let total = Int(value.rounded())
        let hours = total / 60
        let mins = total % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }
}
