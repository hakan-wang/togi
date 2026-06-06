import AppKit
import SwiftUI
import KeyboardShortcuts

// The floating Bogi fish. AppKit/SwiftUI glue only — this file is NOT compiled
// on Linux. All behavioural decisions are delegated to the pure `MascotState`
// and `NudgePolicy`/`NudgePresenter` types so the logic stays testable.

extension KeyboardShortcuts.Name {
    /// "Hey Bogi" — global hotkey to talk to the coach. Default ⌥⌘B; the user
    /// can rebind it in Settings. Registration is wired by the integrator
    /// (see "Integration points" in the PR).
    static let heyBogi = Self("heyBogi", default: .init(.b, modifiers: [.option, .command]))
}

/// Observable view-model the SwiftUI fish renders from. Updated by
/// `MascotController` (which owns the AppKit panel).
@MainActor
final class MascotViewModel: ObservableObject {
    @Published var mood: MascotMood = .idle
    /// Non-nil while a nudge bubble is visible.
    @Published var bubble: BubbleState?

    struct BubbleState: Equatable {
        var message: String
        var severity: NudgeSeverity
        var scale: Double
    }
}

/// The SwiftUI fish + optional speech bubble. Purely presentational; the symbol
/// and tint come from `mood`, and the bubble scales with the nudge severity.
struct MascotFishView: View {
    @ObservedObject var viewModel: MascotViewModel
    /// Forwarded interactions — wired by `MascotController`.
    var onTapFish: () -> Void = {}
    var onDismissBubble: () -> Void = {}

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let bubble = viewModel.bubble {
                speechBubble(bubble)
            }
            fish
        }
        .padding(8)
    }

    private var fish: some View {
        Image(systemName: fishSymbol)
            .resizable()
            .scaledToFit()
            .frame(width: 56, height: 56)
            .foregroundStyle(fishTint)
            .opacity(viewModel.mood == .idle ? 0.7 : 1.0)
            .accessibilityLabel("Bogi")
            .onTapGesture(perform: onTapFish)
    }

    private func speechBubble(_ bubble: MascotViewModel.BubbleState) -> some View {
        Text(bubble.message)
            .font(.callout)
            .multilineTextAlignment(.leading)
            .padding(10)
            .frame(maxWidth: 260 * bubble.scale, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: onDismissBubble) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(4)
            }
            .scaleEffect(bubble.scale)
            // Animate growth so escalation reads as "the fish leaning in".
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: bubble.scale)
    }

    private var fishSymbol: String {
        switch viewModel.mood {
        case .onTask: return "fish.fill"
        case .offTask: return "fish"
        case .idle: return "fish"
        case .speaking: return "bubble.left.fill"
        }
    }

    private var fishTint: Color {
        switch viewModel.mood {
        case .onTask: return .green
        case .offTask: return .orange
        case .idle: return .gray
        case .speaking: return .blue
        }
    }
}

/// Borderless, always-on-top, non-activating panel that hosts the fish. It never
/// steals focus (`becomesKeyOnlyIfNeeded`) and never blocks the screen.
final class MascotPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        // Visible on every Space and over full-screen apps; ignored by Mission
        // Control window cycling so it stays an ambient companion.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Draggable from anywhere on its (transparent) background.
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        // Never take key/main — the fish must not interrupt the user's focus.
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }   // only when explicitly needed (e.g. coach)
    override var canBecomeMain: Bool { false }
}

/// Owns the panel + view-model and bridges them to the mascot's pure logic.
/// Conforms to `NudgeBubblePresenting` so a `NudgePresenter` can drive the
/// bubble without knowing anything about AppKit.
@MainActor
final class MascotController: NudgeBubblePresenting {
    let panel: MascotPanel
    private let viewModel = MascotViewModel()
    /// Set by the integrator; tapping the fish / "Hey Bogi" routes here.
    weak var presenter: NudgePresenter?

    init(initialOrigin: NSPoint = NSPoint(x: 200, y: 200)) {
        let size = NSSize(width: 300, height: 220)
        panel = MascotPanel(contentRect: NSRect(origin: initialOrigin, size: size))
        let root = MascotFishView(
            viewModel: viewModel,
            onTapFish: { [weak self] in self?.handleFishTap() },
            onDismissBubble: { [weak self] in self?.presenter?.dismiss() }
        )
        panel.contentView = NSHostingView(rootView: root)
        applyMood(.idle)
    }

    /// Show the panel without activating the app.
    func show() {
        panel.orderFrontRegardless()
    }

    /// Update the fish to reflect the latest app state (delegates to `MascotState`).
    func update(input: MascotInput) {
        applyMood(MascotState.mood(for: input))
    }

    private func applyMood(_ mood: MascotMood) {
        viewModel.mood = mood
        // Click-through where idle: when the fish is just floating it shouldn't
        // intercept clicks meant for windows behind it. Any other mood (or a
        // visible bubble) is interactive.
        panel.ignoresMouseEvents = (mood == .idle && viewModel.bubble == nil)
    }

    /// Register the "Hey Bogi" global hotkey. Call from the integrator at launch.
    func registerHeyBogiHotkey() {
        KeyboardShortcuts.onKeyUp(for: .heyBogi) { [weak self] in
            self?.handleFishTap()
        }
    }

    /// Current panel frame as a framework-light anchor for the coach.
    private var anchor: MascotAnchor {
        let f = panel.frame
        return MascotAnchor(x: Double(f.origin.x), y: Double(f.origin.y),
                            width: Double(f.size.width), height: Double(f.size.height))
    }

    private func handleFishTap() {
        presenter?.openCoach(anchoredTo: anchor, prompt: nil)
    }

    // MARK: - NudgeBubblePresenting

    func showBubble(message: String, decision: NudgeDecision) {
        viewModel.bubble = MascotViewModel.BubbleState(
            message: message, severity: decision.severity, scale: decision.scale
        )
        // While speaking, the panel must accept clicks (dismiss / talk back).
        viewModel.mood = .speaking
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        if decision.playSound {
            NSSound.beep()
        }
    }

    func hideBubble() {
        viewModel.bubble = nil
        // Fall back to a non-speaking, click-through idle until the next state
        // update from the judge/capture refreshes the mood.
        applyMood(.idle)
    }
}
