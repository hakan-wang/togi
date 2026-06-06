import SwiftUI

/// The Bogi companion: a compact frosted-glass panel. Primary page is the coach chat;
/// the chart button in the top toolbar flips to the dashboard (Day/Week/Month/Year
/// insights). Styled per the brand: frosted glass, sky tint, sky-blue accent.
struct CompanionView: View {
    enum Page { case chat, dashboard }

    let insight: (DashboardPeriod) -> PeriodInsight
    let ask: (String) async throws -> String
    var onSettings: () -> Void = {}
    var onClose: () -> Void = {}

    @State private var page: Page = .chat
    @State private var period: DashboardPeriod = .day

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.4)
            content
        }
        .frame(width: 420, height: 520)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        )
    }

    // MARK: - Top toolbar (the row of buttons)

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("bogi")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(BogiColor.ink)
            Spacer()
            iconButton("bubble.left.and.bubble.right.fill", active: page == .chat) {
                withAnimation(.easeInOut(duration: 0.22)) { page = .chat }
            }
            iconButton("chart.bar.fill", active: page == .dashboard) {
                withAnimation(.easeInOut(duration: 0.22)) { page = .dashboard }
            }
            iconButton("gearshape.fill", active: false, action: onSettings)
            iconButton("xmark", active: false, action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func iconButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.white : BogiColor.muted)
                .frame(width: 26, height: 26)
                .background(active ? BogiColor.primary : Color.white.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pages

    @ViewBuilder
    private var content: some View {
        switch page {
        case .chat:
            CoachView(ask: ask)
                .transition(.opacity.combined(with: .move(edge: .leading)))
        case .dashboard:
            dashboardPage
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var dashboardPage: some View {
        VStack(spacing: 12) {
            Picker("", selection: $period) {
                Text("Day").tag(DashboardPeriod.day)
                Text("Week").tag(DashboardPeriod.week)
                Text("Month").tag(DashboardPeriod.month)
                Text("Year").tag(DashboardPeriod.year)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                InsightView(insight: insight(period))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Frosted background

    private var panelBackground: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)          // frosts the desktop behind the panel
            BogiGradient.sky.opacity(0.30)              // dreamy sky tint
        }
    }
}

#if DEBUG
#Preview {
    CompanionView(
        insight: { _ in
            PeriodInsight(
                label: "2026-06-06", totalMinutes: 180, onTaskMinutes: 120,
                categories: [
                    CategoryTotal(category: "work", minutes: 120, onTaskMinutes: 110),
                    CategoryTotal(category: "social", minutes: 60, onTaskMinutes: 10),
                ],
                blocks: []
            )
        },
        ask: { _ in try await Task.sleep(nanoseconds: 300_000_000); return "you spent most of the hour in the editor. good." }
    )
    .frame(width: 420, height: 520)
    .padding(40)
    .background(Color.black)
}
#endif
