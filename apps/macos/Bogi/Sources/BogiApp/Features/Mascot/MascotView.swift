import SwiftUI

/// The floating mascot: the plush axolotl logo, calmly hovering and bobbing. A soft halo
/// behind it tints with mood (green on-task, amber off-task). Clicking it opens Bogi.
/// The optional speech bubble stays quiet at low escalation and grows if ignored — never
/// a blocking wall.
struct MascotView: View {
    @ObservedObject var viewModel: MascotViewModel
    var onActivate: (() -> Void)?

    var body: some View {
        ZStack {
            // The voice aura sits behind everything, centered, free to grow with the volume.
            voiceGlow

            VStack(spacing: 8) {
                // Voice is voice. No captions, no status text, no bubble — the aura is the
                // whole visual; Togi replies out loud. Nudges (the only other source of bubble
                // text) are suppressed while a voice exchange is active so they can't sneak in
                // beside the aura.
                if !viewModel.voiceActive, let text = viewModel.bubbleText {
                    SpeechBubble(text: text, escalationLevel: viewModel.escalationLevel)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Button {
                    onActivate?()
                } label: {
                    mascotPlush
                        .background(halo)
                        .shadow(color: Color(hex: 0x285078).opacity(0.22), radius: 11, y: 7)
                        .scaleEffect(escalationScale)
                        .bob(distance: 6, duration: 3.4)
                }
                .buttonStyle(.plain)
                .help("Open Togi")
                .accessibilityLabel("Togi")
            }
        }
        // Fill the whole panel so the aura has room and isn't boxed to the axolotl's frame.
        .frame(width: 220, height: 220)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.bubbleText)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.voiceActive)
        .animation(.easeInOut(duration: 0.25), value: viewModel.escalationLevel)
        .animation(.easeInOut(duration: 0.9), value: viewModel.vitality)
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

    /// A soft light behind the axolotl that grows and shrinks with your voice while recording.
    /// This is the live volume meter: bigger and brighter as you speak, fading out when idle.
    private var voiceGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [BogiColor.primary.opacity(0.8), BogiColor.primary.opacity(0)],
                    center: .center, startRadius: 6, endRadius: 90
                )
            )
            .frame(width: 176, height: 176)
            .blur(radius: 12)
            .scaleEffect(viewModel.voiceActive ? 0.45 + CGFloat(viewModel.voiceLevel) * 0.65 : 0.35)
            .opacity(viewModel.voiceActive ? 0.4 + Double(viewModel.voiceLevel) * 0.6 : 0)
            .animation(.easeOut(duration: 0.1), value: viewModel.voiceLevel)
            .animation(.easeInOut(duration: 0.35), value: viewModel.voiceActive)
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

    /// The plush at its fixed size — reused as both the fill and the tint mask.
    private var plushImage: some View {
        BogiAsset.mascot
            .resizable()
            .scaledToFit()
            .frame(width: 108, height: 108)
    }

    /// The mascot tinted by wellbeing: baby-blue when thriving, flushing toward a deep red
    /// the more unproductive (lower vitality) you are. A `.color` blend recolours the plush
    /// while keeping all its shading; brightness/saturation deepen the red at the low end.
    private var mascotPlush: some View {
        plushImage
            .overlay(
                Color(hex: 0xcf1d14)
                    .opacity(look.washOpacity)
                    .blendMode(.color)
                    .mask(plushImage)
            )
            .saturation(1.0 + 0.25 * look.redness)
            .brightness(-0.18 * look.redness)
            .compositingGroup()
    }
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
