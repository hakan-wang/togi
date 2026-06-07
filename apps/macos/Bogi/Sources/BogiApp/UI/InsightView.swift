import SwiftUI

/// Renders a single `PeriodInsight`: how the period's time was spent and how the plan
/// held up against reality. Pure rendering — all numbers come from the injected insight.
struct InsightView: View {
    let insight: PeriodInsight
    /// When embedded, render the content without an owning `ScrollView` (and without the
    /// outer padding) so a host can stack it above other sections in a single scroll.
    var embedded: Bool = false

    var body: some View {
        if embedded {
            content
        } else {
            ScrollView { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            categoriesSection
            if !insight.blocks.isEmpty {
                blocksSection
            }
        }
        .padding(embedded ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(insight.label)
                    .font(.title2).bold()
                Spacer()
                Text("\(onTaskPercent)% on task")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            RatioBar(fraction: onTaskFraction, tint: .green)
                .frame(height: 10)

            Text("\(minutesLabel(insight.onTaskMinutes)) on task of \(minutesLabel(insight.totalMinutes)) tracked")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var onTaskFraction: Double {
        guard insight.totalMinutes > 0 else { return 0 }
        return min(1, insight.onTaskMinutes / insight.totalMinutes)
    }

    private var onTaskPercent: Int {
        Int((onTaskFraction * 100).rounded())
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where your time went")
                .font(.headline)

            if insight.categories.isEmpty {
                Text("No tracked time yet for this period.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(insight.categories, id: \.category) { category in
                    CategoryRow(category: category,
                                maxMinutes: maxCategoryMinutes,
                                minutesLabel: minutesLabel)
                }
            }
        }
    }

    private var maxCategoryMinutes: Double {
        max(insight.categories.map(\.minutes).max() ?? 0, 1)
    }

    // MARK: - Plan vs reality

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan vs reality")
                .font(.headline)

            ForEach(insight.blocks, id: \.blockTitle) { block in
                BlockRow(block: block, minutesLabel: minutesLabel)
            }
        }
    }

    // MARK: - Formatting

    /// Formats a minute count as a compact "1h 12m" / "45m" string.
    func minutesLabel(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let hours = total / 60
        let mins = total % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }
}

// MARK: - Rows

private struct CategoryRow: View {
    let category: CategoryTotal
    let maxMinutes: Double
    let minutesLabel: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(category.category)
                    .font(.callout)
                Spacer()
                Text(minutesLabel(category.minutes))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Bar length is proportional to this category's share of the busiest
            // category; the green portion shows the on-task share within it.
            SplitBar(total: category.minutes,
                     onTask: category.onTaskMinutes,
                     scale: maxMinutes)
                .frame(height: 8)
        }
    }
}

private struct BlockRow: View {
    let block: BlockComparison
    let minutesLabel: (Double) -> String

    private var scale: Double {
        max(block.plannedMinutes, block.onTaskMinutes + block.offTaskMinutes, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(block.blockTitle)
                    .font(.callout)
                Spacer()
                Text("planned \(minutesLabel(block.plannedMinutes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            SplitBar(total: block.onTaskMinutes + block.offTaskMinutes,
                     onTask: block.onTaskMinutes,
                     scale: scale)
                .frame(height: 8)

            HStack(spacing: 12) {
                Label(minutesLabel(block.onTaskMinutes), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label(minutesLabel(block.offTaskMinutes), systemImage: "xmark.circle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Bars

/// A single-color progress bar filled to `fraction` (0...1).
private struct RatioBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
    }
}

/// A bar whose overall length reflects `total / scale`, split into an on-task (green)
/// portion and an off-task (orange) remainder.
private struct SplitBar: View {
    let total: Double
    let onTask: Double
    let scale: Double

    var body: some View {
        GeometryReader { geo in
            let fullWidth = geo.size.width * min(max(total / max(scale, 1), 0), 1)
            let onTaskWidth = total > 0 ? fullWidth * min(max(onTask / total, 0), 1) : 0

            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.orange.opacity(0.85))
                    .frame(width: fullWidth)
                Capsule()
                    .fill(Color.green.opacity(0.9))
                    .frame(width: onTaskWidth)
            }
        }
    }
}

#if DEBUG
#Preview("Day insight") {
    InsightView(insight: PeriodInsight(
        label: "Today",
        totalMinutes: 410,
        onTaskMinutes: 268,
        categories: [
            CategoryTotal(category: "Deep work", minutes: 185, onTaskMinutes: 170),
            CategoryTotal(category: "Email & Slack", minutes: 92, onTaskMinutes: 40),
            CategoryTotal(category: "Social media", minutes: 73, onTaskMinutes: 0),
            CategoryTotal(category: "Meetings", minutes: 60, onTaskMinutes: 58)
        ],
        blocks: [
            BlockComparison(blockTitle: "Morning: ship deck", plannedMinutes: 120, onTaskMinutes: 95, offTaskMinutes: 25),
            BlockComparison(blockTitle: "Afternoon: deep work", plannedMinutes: 180, onTaskMinutes: 140, offTaskMinutes: 30)
        ]
    ))
    .frame(width: 420, height: 520)
}
#endif
