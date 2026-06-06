import SwiftUI

/// The floating mascot view. Placeholder art: an SF Symbol fish whose color and size
/// reflect the current mood, with an optional non-modal speech bubble above it.
///
/// Clicking the fish invokes `onActivate` (the "open coach chat" hook). The bubble is
/// deliberately small and quiet at low escalation and grows as escalation rises — it
/// must never become a blocking wall.
struct MascotView: View {
    @ObservedObject var viewModel: MascotViewModel

    /// Hook fired when the user clicks the mascot ("Hey Bogi" / open coach chat).
    var onActivate: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            if let text = viewModel.bubbleText {
                SpeechBubble(text: text, escalationLevel: viewModel.escalationLevel)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Button(action: { onActivate?() }) {
                Image(systemName: "fish.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: fishSize, height: fishSize)
                    .foregroundStyle(moodColor)
                    .padding(16)
                    .background(.thinMaterial, in: Circle())
                    .scaleEffect(escalationScale)
            }
            .buttonStyle(.plain)
            .help("Open Bogi coach")
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.bubbleText)
        .animation(.easeInOut(duration: 0.25), value: viewModel.escalationLevel)
        .padding(8)
    }

    // MARK: - Mood-driven appearance

    private var moodColor: Color {
        switch viewModel.mood {
        case .idle:     return .gray
        case .onTask:   return Color.green.opacity(0.9)
        case .offTask:  return .orange
        case .speaking: return viewModel.escalationLevel >= 2 ? .red : .orange
        }
    }

    private var fishSize: CGFloat { 56 }

    /// Subtle growth as escalation climbs so an ignored nudge gets more visible
    /// without ever becoming modal.
    private var escalationScale: CGFloat {
        1.0 + (CGFloat(viewModel.escalationLevel) * 0.08)
    }
}

/// Small non-modal callout above the fish. Tone is blunt, not naggy — that copy is
/// supplied by the caller; this view just renders it.
private struct SpeechBubble: View {
    let text: String
    let escalationLevel: Int

    var body: some View {
        Text(text)
            .font(escalationLevel >= 2 ? .callout.bold() : .caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 220)
            .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(escalationLevel >= 2 ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
            .shadow(radius: 4, y: 2)
    }

    private var bubbleBackground: some ShapeStyle {
        escalationLevel >= 2 ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thinMaterial)
    }
}

#if DEBUG
#Preview("Off-task, escalated") {
    MascotView(viewModel: {
        let vm = MascotViewModel(mood: .speaking,
                                 bubbleText: "You opened Twitter 4 minutes ago. That's not the deck.",
                                 escalationLevel: 2)
        return vm
    }())
    .frame(width: 260, height: 200)
}

#Preview("On task") {
    MascotView(viewModel: MascotViewModel(mood: .onTask))
        .frame(width: 160, height: 160)
}
#endif
