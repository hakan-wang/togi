import AppKit
import SwiftUI

/// The floating mascot: the plush axolotl logo, calmly hovering and bobbing. A soft halo
/// behind it tints with mood (green on-task, amber off-task). A *click* opens Bogi; a
/// *press-and-drag* moves the mascot without opening anything. The optional speech bubble
/// stays quiet at low escalation and grows if ignored — never a blocking wall.
struct MascotView: View {
    @ObservedObject var viewModel: MascotViewModel
    var onActivate: (() -> Void)?

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
        VStack(spacing: 8) {
            if let text = viewModel.bubbleText {
                SpeechBubble(text: text, escalationLevel: viewModel.escalationLevel)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            BogiAsset.mascot
                .resizable()
                .scaledToFit()
                .frame(width: 81, height: 81)
                .saturation(look.saturation)
                .grayscale(look.grayscale)
                .background(halo)
                .shadow(color: Color(hex: 0x285078).opacity(0.30), radius: 13, y: 9)
                .scaleEffect(escalationScale * look.scale)
                .offset(y: look.droopY)
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
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.bubbleText)
        .animation(.easeInOut(duration: 0.25), value: viewModel.escalationLevel)
        .animation(.easeInOut(duration: 0.9), value: viewModel.vitality)
        .padding(8)
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
