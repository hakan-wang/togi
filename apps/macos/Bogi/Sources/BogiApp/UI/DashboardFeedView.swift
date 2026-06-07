import SwiftUI

/// "What Togi noticed" — a stack of behavioural insight cards. Read-only; the agent curates
/// what appears (and dismisses) via the journal. Pure rendering, like `InsightView`.
struct NoticeSection: View {
    let cards: [InsightCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What Togi noticed")
                .font(.headline)

            if cards.isEmpty {
                Text("No insights yet. Togi notes patterns as it learns how you work.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cards) { InsightCardRow(card: $0) }
            }
        }
    }
}

private struct InsightCardRow: View {
    let card: InsightCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title)
                    .font(.callout.weight(.semibold))
                Spacer()
                if let c = card.confidence {
                    Text("\(Int((c * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let detail = card.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardChrome()
    }
}

/// "Goals" — active goals with the next check-in and a short journey timeline. Read-only.
struct GoalsSection: View {
    let goals: [GoalCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Goals")
                .font(.headline)

            if goals.isEmpty {
                Text("No goals yet. Tell Togi a goal in chat and it will track it with you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(goals) { GoalCardRow(card: $0) }
            }
        }
    }
}

private struct GoalCardRow: View {
    let card: GoalCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title)
                    .font(.callout.weight(.semibold))
                Spacer()
                if let next = card.nextCheckIn {
                    Label(relative(next), systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(BogiColor.primary)
                }
            }

            if let why = card.why, !why.isEmpty {
                Text(why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !card.journey.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(card.journey) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(BogiColor.mascotBlue)
                                .frame(width: 5, height: 5)
                            Text(entry.text)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .cardChrome()
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

private extension View {
    /// The shared compact card look used by both sections (frosted, hairline-stroked).
    func cardChrome() -> some View {
        self
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
    }
}
