import SwiftUI

/// The floating mascot: the plush axolotl logo, calmly hovering and bobbing. A soft halo
/// behind it tints with mood (green on-task, amber off-task). Clicking it opens Bogi.
/// The optional speech bubble stays quiet at low escalation and grows if ignored — never
/// a blocking wall.
struct MascotView: View {
    @ObservedObject var viewModel: MascotViewModel
    var onActivate: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            if let text = viewModel.bubbleText {
                SpeechBubble(text: text, escalationLevel: viewModel.escalationLevel)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Button(action: { onActivate?() }) {
                BogiAsset.mascot
                    .resizable()
                    .scaledToFit()
                    .frame(width: 108, height: 108)
                    .saturation(look.saturation)
                    .grayscale(look.grayscale)
                    .background(halo)
                    .shadow(color: Color(hex: 0x285078).opacity(0.22), radius: 11, y: 7)
                    .scaleEffect(escalationScale * look.scale)
                    .offset(y: look.droopY)
                    .bob(distance: look.bobDistance, duration: look.bobDuration)
            }
            .buttonStyle(.plain)
            .help("Open Togi")
            .accessibilityLabel("Togi")
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.bubbleText)
        .animation(.easeInOut(duration: 0.25), value: viewModel.escalationLevel)
        .animation(.easeInOut(duration: 0.9), value: viewModel.vitality)
        .padding(8)
    }

    // MARK: - Mood halo (the plush art is fixed, so mood reads as a soft glow behind it)

    private var halo: some View {
        Circle()
            .fill(haloColor)
            .blur(radius: 24)
            .frame(width: 128, height: 128)
            .opacity(viewModel.mood == .idle ? 0 : 0.55)
            .animation(.easeInOut(duration: 0.4), value: viewModel.mood)
    }

    private var haloColor: Color {
        switch viewModel.mood {
        case .idle:     return .clear
        case .onTask:   return Color.green.opacity(0.8)
        case .offTask:  return Color.orange.opacity(0.85)
        case .speaking: return viewModel.escalationLevel >= 2 ? Color.red.opacity(0.85) : Color.orange.opacity(0.85)
        }
    }

    private var escalationScale: CGFloat {
        1.0 + (CGFloat(viewModel.escalationLevel) * 0.07)
    }

    /// How alive the body looks, derived from wellbeing (0…100).
    private var look: VitalityLook { VitalityLook(viewModel.vitality) }
}

/// Small non-modal callout above the mascot. Blunt, not naggy — copy comes from the caller.
private struct SpeechBubble: View {
    let text: String
    let escalationLevel: Int

    var body: some View {
        Text(text)
            .font(escalationLevel >= 2 ? .callout.bold() : .caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(BogiColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(escalationLevel >= 2 ? Color.red.opacity(0.6) : Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x285078).opacity(0.25), radius: 8, y: 4)
    }
}

#if DEBUG
#Preview("Off-task, escalated") {
    MascotView(viewModel: MascotViewModel(
        mood: .speaking,
        bubbleText: "you opened twitter 4 minutes ago. that's not the deck.",
        escalationLevel: 2
    ))
    .frame(width: 280, height: 220)
    .padding()
}
#endif
