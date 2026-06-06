import SwiftUI

/// Main window content: a period picker driving an `InsightView`, with the coach chat
/// docked alongside. Fully injected — no services, so it compiles against the shared
/// DataBank structs alone.
struct DashboardView: View {
    /// Supplies the insight for the selected period.
    let insight: (DashboardPeriod) -> PeriodInsight
    /// Forwarded to the embedded `CoachView`.
    let ask: (_ question: String, _ onToken: @escaping (String) -> Void) async throws -> String

    @State private var period: DashboardPeriod = .day

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                periodPicker
                    .padding(12)
                Divider()
                InsightView(insight: insight(period))
            }
            .frame(minWidth: 380, idealWidth: 440)

            VStack(alignment: .leading, spacing: 0) {
                Text("Coach")
                    .font(.headline)
                    .padding(12)
                Divider()
                CoachView(ask: ask)
            }
            .frame(minWidth: 260, idealWidth: 280)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 420, idealHeight: 520)
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            Text("Day").tag(DashboardPeriod.day)
            Text("Week").tag(DashboardPeriod.week)
            Text("Month").tag(DashboardPeriod.month)
            Text("Year").tag(DashboardPeriod.year)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

#if DEBUG
#Preview("Dashboard") {
    DashboardView(
        insight: { period in
            let label: String
            let total: Double
            switch period {
            case .day:   label = "Today";        total = 410
            case .week:  label = "This week";    total = 2380
            case .month: label = "This month";   total = 9600
            case .year:  label = "This year";    total = 112000
            }
            return PeriodInsight(
                label: label,
                totalMinutes: total,
                onTaskMinutes: total * 0.62,
                categories: [
                    CategoryTotal(category: "Deep work", minutes: total * 0.45, onTaskMinutes: total * 0.42),
                    CategoryTotal(category: "Email & Slack", minutes: total * 0.22, onTaskMinutes: total * 0.10),
                    CategoryTotal(category: "Social media", minutes: total * 0.18, onTaskMinutes: 0),
                    CategoryTotal(category: "Meetings", minutes: total * 0.15, onTaskMinutes: total * 0.14)
                ],
                blocks: [
                    BlockComparison(blockTitle: "Morning: ship deck", plannedMinutes: 120, onTaskMinutes: 95, offTaskMinutes: 25),
                    BlockComparison(blockTitle: "Afternoon: deep work", plannedMinutes: 180, onTaskMinutes: 140, offTaskMinutes: 30)
                ]
            )
        },
        ask: { _, _ in
            try? await Task.sleep(nanoseconds: 500_000_000)
            return "You're at 62% on task. The leak is email — 22% of your time, almost none of it on plan."
        }
    )
}
#endif
