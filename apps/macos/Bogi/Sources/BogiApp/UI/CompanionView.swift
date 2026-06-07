import SwiftUI
import Combine

/// The Togi companion: a light liquid-glass command bar that grows with the conversation.
/// It opens almost empty (just the input and a few live openers) and reports its rendered
/// height to the host panel so the window can size to fit, capped so it never fills the
/// screen. The chart button flips to the dashboard (Day/Week/Month/Year insights).
struct CompanionView: View {
    enum Page { case chat, dashboard, settings }

    let insight: (DashboardPeriod) -> PeriodInsight
    let ask: (_ question: String, _ onToken: @escaping (String) -> Void) async throws -> String
    /// Active behavioural insights ("Notice") shown below the period stats. Period-independent.
    var insightCards: () -> [InsightCard] = { [] }
    /// Active goals with their next check-in and recent journey, shown below the insights.
    var goalCards: () -> [GoalCard] = { [] }
    /// Live conversation openers for the empty chat state. Injected by the host.
    var suggest: () -> [String] = { [] }
    /// The tallest the card may grow. Used to cap the transcript and the dashboard.
    var maxContentHeight: CGFloat = 600
    /// Reports the card's current rendered height so the panel can resize to fit.
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var onSettings: () -> Void = {}
    var onClose: () -> Void = {}
    /// Resets the agent's conversation thread when the user clears the chat, so it forgets the
    /// prior exchange. The visible transcript is cleared separately via `.companionClearChat`.
    var onClearChat: () -> Void = {}
    /// Pre-seeded transcript for previews and the screenshot demo hook. Empty in the real app.
    var seedMessages: [(role: String, text: String)] = []

    @State private var page: Page = .chat
    @State private var period: DashboardPeriod = .day
    /// Whether the chat holds any messages — drives the "clear chat" button's visibility.
    @State private var chatHasMessages = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.35)
            content
        }
        .frame(width: 420)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { onHeightChange(geo.size.height) }
                    .onChange(of: geo.size.height) { _, height in onHeightChange(height) }
            }
        )
        .onExitCommand { onClose() }
        .onReceive(NotificationCenter.default.publisher(for: .companionDidOpen)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { page = .chat }
        }
    }

    // MARK: - Top toolbar (the row of buttons)

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("togi")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.primary)
            Spacer()
            iconButton("bubble.left.and.bubble.right.fill", active: page == .chat) {
                withAnimation(.easeInOut(duration: 0.22)) { page = .chat }
            }
            iconButton("chart.bar.fill", active: page == .dashboard) {
                withAnimation(.easeInOut(duration: 0.22)) { page = .dashboard }
            }
            iconButton("gearshape.fill", active: page == .settings) {
                withAnimation(.easeInOut(duration: 0.22)) { page = .settings }
            }
            // Clear chat: only on the chat page, only once there's something to clear. Wipes the
            // transcript (via notification) and rotates the agent's thread (via onClearChat).
            if page == .chat, chatHasMessages {
                iconButton("trash", active: false) {
                    onClearChat()
                    NotificationCenter.default.post(name: .companionClearChat, object: nil)
                }
            }
            iconButton("xmark", active: false, action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func iconButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.white : BogiColor.muted)
                .frame(width: 26, height: 26)
                .background(active ? AnyShapeStyle(BogiColor.primary) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(active ? 0 : 0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pages

    @ViewBuilder
    private var content: some View {
        switch page {
        case .chat:
            CoachView(
                ask: ask,
                suggest: suggest,
                transcriptMaxHeight: max(160, maxContentHeight - 140),
                seedMessages: seedMessages,
                onHasMessagesChange: { chatHasMessages = $0 }
            )
            .transition(.opacity.combined(with: .move(edge: .leading)))
        case .dashboard:
            dashboardPage
                .frame(height: max(260, maxContentHeight - 44))
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        case .settings:
            CompanionSettingsView()
                .transition(.opacity)
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
                VStack(alignment: .leading, spacing: 20) {
                    InsightView(insight: insight(period), embedded: true)
                    NoticeSection(cards: insightCards())
                    GoalsSection(goals: goalCards())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Liquid-glass background

    private var panelBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)                 // see-through frosted glass
            LinearGradient(                                      // a hint of light across the top
                colors: [Color.white.opacity(0.14), .clear],
                startPoint: .top, endPoint: .center
            )
            BogiGradient.sky.opacity(0.08)                       // faint brand tint, not a wash
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
        ask: { _, _ in try await Task.sleep(nanoseconds: 300_000_000); return "you spent most of the hour in the editor. good." },
        suggest: { ["why did i lose 50 min to social?", "where did my time go today?", "what should i focus on next?"] }
    )
    .frame(width: 420)
    .padding(40)
    .background(Color.black)
}
#endif
