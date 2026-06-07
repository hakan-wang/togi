import AppKit
import SwiftUI

/// The floating mascot: the plush axolotl logo, calmly hovering and bobbing. A soft halo
/// behind it tints with mood (green on-task, amber off-task). A *click* opens Bogi; a
/// *press-and-drag* moves the mascot without opening anything. The optional speech bubble
/// stays quiet at low escalation and grows if ignored — never a blocking wall. A reactive
/// aura blooms behind the plush while a voice exchange is recording.
struct MascotView: View {
    @ObservedObject var viewModel: MascotViewModel
    var onActivate: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swaying = false

    // Drag-vs-click tracking. We can't rely on `DragGesture`'s `translation` because the
    // panel follows the cursor while dragging (the gesture's local space moves with it, so
    // translation stays ~0). Instead we sample the pointer in *screen* space via
    // `NSEvent.mouseLocation` and move the window ourselves.
    @State private var hostWindow: NSWindow?
    @State private var dragStartMouse: NSPoint?
    @State private var dragStartOrigin: NSPoint?
    @State private var didDrag = false

    /// How far the pointer must travel (points, screen space) before a press counts as a
    /// drag rather than a click. Small enough that real clicks always register.
    private let dragThreshold: CGFloat = 4

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

                ZStack {
                    BogiAsset.mascot
                        .resizable()
                        .scaledToFit()
                        .frame(width: 81, height: 81)
                    expressionMouth                                              // drawn mouth: smile → flat → frown
                }
                .saturation(max(0.12, look.saturation - 0.22 * discomfort))      // drifting drains the colour
                .grayscale(look.grayscale)
                .brightness(-0.05 * discomfort)                                  // and dims it a touch
                .background(halo)
                .shadow(color: Color(hex: 0x285078).opacity(0.30), radius: 13, y: 9)
                .scaleEffect(escalationScale * look.scale * (1 - 0.04 * discomfort))  // pulls in, uneasy
                .rotationEffect(.degrees(sway))                                  // tired lean + nervous sway
                .offset(y: look.droopY + 9 * discomfort)                         // slumps when off task
                .bob(distance: look.bobDistance, duration: look.bobDuration)
                .contentShape(Rectangle())
                .gesture(dragOrTap)
                .help("Open Togi")
                .accessibilityElement()
                .accessibilityLabel("Togi")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onActivate?() }
                .background(WindowAccessor { hostWindow = $0 })
            }
        }
        // Fill the whole panel so the aura has room and isn't boxed to the axolotl's frame.
        .frame(width: 220, height: 220)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.bubbleText)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.voiceActive)
        .animation(.easeInOut(duration: 0.25), value: viewModel.escalationLevel)
        .animation(.easeInOut(duration: 0.9), value: viewModel.vitality)
        .animation(.easeInOut(duration: 0.4), value: viewModel.mood)
        .padding(8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                swaying = true
            }
        }
    }

    /// A single gesture that doubles as click and drag: a release with little movement
    /// opens Bogi; anything past `dragThreshold` repositions the panel and suppresses the
    /// open. `minimumDistance: 0` so a plain click (no movement) still ends the gesture.
    private var dragOrTap: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                if dragStartMouse == nil {
                    dragStartMouse = mouse
                    dragStartOrigin = hostWindow?.frame.origin
                    didDrag = false
                }
                guard let start = dragStartMouse else { return }
                let dx = mouse.x - start.x
                let dy = mouse.y - start.y
                if hypot(dx, dy) > dragThreshold { didDrag = true }
                if didDrag, let origin = dragStartOrigin {
                    hostWindow?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
                }
            }
            .onEnded { _ in
                let wasClick = !didDrag
                dragStartMouse = nil
                dragStartOrigin = nil
                didDrag = false
                if wasClick { onActivate?() }
            }
    }

    // MARK: - Mood halo (the plush art is fixed, so mood reads as a soft glow behind it)

    private var halo: some View {
        // A soft radial glow that fades to transparent at its edge, so the mood reads as a
        // gentle aura behind the mascot rather than a flat blurred disc / brown box on a
        // dark wallpaper. `haloColor` already carries its own opacity; the gradient tapers it.
        RadialGradient(
            colors: [haloColor.opacity(0.40), haloColor.opacity(0)],
            center: .center,
            startRadius: 2,
            endRadius: 52
        )
        .frame(width: 104, height: 104)
        .blur(radius: 6)
        .opacity(viewModel.mood == .idle ? 0 : 1)
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

    /// 0 when the user is fine; rises when they're off task right now, and again as a nudge
    /// escalates. Drives the immediate "tired / uncomfortable" read on the body — slump, dim,
    /// shrink, nervous sway — layered on top of the slow vitality wilt.
    private var discomfort: CGFloat {
        switch viewModel.mood {
        case .speaking: return min(1.6, 1.0 + 0.2 * CGFloat(viewModel.escalationLevel))
        case .offTask:  return 1.0
        default:        return 0          // idle / on task sit comfortably
        }
    }

    /// A small uneasy lean that gently sways while the user is off task; flat otherwise.
    private var sway: Double {
        guard discomfort > 0 else { return 0 }
        let amplitude = 2.2 * Double(min(discomfort, 1.6))
        return swaying ? amplitude : -amplitude
    }

    // MARK: - Drawn mouth (the art has a fixed smile, so we overpaint the expression)

    /// Covers the baked-in smile with the body colour and draws the current mouth on top, so
    /// the face can actually change: a smile when well, a flat line when drifting, a frown
    /// while being nudged. The whole stack desaturates with the body.
    private var expressionMouth: some View {
        ZStack {
            Capsule()
                .fill(Color(hex: 0xa9d0d9))
                .frame(width: 30, height: 13)
            MouthShape(curve: mouthCurve)
                .stroke(Color(hex: 0x33302c), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .frame(width: 21, height: 11)
        }
        .offset(y: 12)
        .animation(.easeInOut(duration: 0.4), value: mouthCurve)
    }

    /// +1 = smile, 0 = flat, -1 = frown.
    private var mouthCurve: CGFloat {
        switch viewModel.mood {
        case .speaking: return -1                                  // sad while being nudged
        case .offTask:  return 0                                   // flat / unimpressed
        case .onTask:   return 1                                   // happy
        case .idle:     return viewModel.vitality < 35 ? -0.4 : 1  // droops when truly drained
        }
    }
}

/// A mouth that morphs between a smile (curve = +1), a flat line (0), and a frown (-1).
private struct MouthShape: Shape {
    var curve: CGFloat
    var animatableData: CGFloat {
        get { curve }
        set { curve = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dip = rect.height * curve * 0.6   // middle dips down for a smile, up for a frown
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.midY + dip)
        )
        return path
    }
}

/// Small non-modal callout above the mascot. Supportive, not naggy. Copy comes from the caller.
private struct SpeechBubble: View {
    let text: String
    let escalationLevel: Int

    var body: some View {
        Text(text)
            .font(escalationLevel >= 2 ? .callout.bold() : .caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(BogiColor.ink)
            // Take the full multi-line height so the nudge wraps instead of truncating to
            // one clipped line ("Hey, you j…") inside the panel.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 200)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(escalationLevel >= 2 ? Color.red.opacity(0.6) : Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x285078).opacity(0.25), radius: 8, y: 4)
    }
}

/// Hands the enclosing `NSWindow` back to SwiftUI once the view is in a window, so the
/// mascot's drag gesture can reposition the panel directly. Renders nothing.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
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
