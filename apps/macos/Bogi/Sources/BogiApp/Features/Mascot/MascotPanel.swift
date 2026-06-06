import AppKit
import SwiftUI

/// Floating mascot — a borderless, always-on-top, non-activating panel that hosts
/// `MascotView`. It owns a `MascotViewModel` (the observable state SwiftUI renders)
/// and forwards clicks via `onActivate`. Mood/nudge logic lives elsewhere
/// (`NudgePresenter` + the AppDelegate); this panel is just the window shell.
@MainActor
final class MascotPanel: NSPanel {
    /// Observable state driving the mascot's appearance. Push updates here (or call
    /// `update(mood:)`) to change what the fish shows.
    let viewModel: MascotViewModel

    /// Fired when the user clicks the mascot ("Hey Bogi" → open coach chat). The
    /// owner installs this; the panel never opens chat itself.
    var onActivate: (() -> Void)? {
        didSet { /* captured by reference in the hosted view's closure */ }
    }

    /// True once we've placed the panel at its default resting spot. After that,
    /// `show()` preserves wherever the user last dragged it instead of snapping back.
    private var hasSetInitialPosition = false

    init(viewModel: MascotViewModel? = nil) {
        self.viewModel = viewModel ?? MascotViewModel()
        super.init(
            // Wide/tall enough that a multi-line nudge bubble (maxWidth 200) wraps and the
            // mascot's mood glow sits within the transparent panel without clipping.
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 210),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false                   // no boxy window-shadow ring around the mascot
        // The mascot view drives repositioning itself (so it can tell a drag from a click);
        // leaving window-background move on would fight that and double-move the panel.
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Route the view's tap through this panel's `onActivate` so the owner can swap
        // the closure at any time without rebuilding the hosting view.
        let root = MascotView(viewModel: self.viewModel, onActivate: { [weak self] in
            self?.onActivate?()
        })
        contentView = NSHostingView(rootView: root)
    }

    func show() {
        // Bottom-right of the main screen as a default resting spot — only on the
        // first reveal. Subsequent shows (e.g. after hide, or a nudge auto-reappear)
        // keep the position the user last dragged the mascot to.
        if !hasSetInitialPosition, let screen = NSScreen.main {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: frame.maxX - 264, y: frame.minY + 72))
            hasSetInitialPosition = true
        }
        orderFrontRegardless()
    }

    /// Take the mascot off-screen without tearing down the panel. `show()` brings it
    /// back at its last position.
    func hide() {
        orderOut(nil)
    }

    /// Convenience for the common case of just changing mood.
    func update(mood: MascotMood) {
        viewModel.mood = mood
    }

    /// Apply a presenter decision (bubble text + escalation + speaking mood).
    func apply(_ decision: NudgeDecision) {
        viewModel.apply(decision)
    }

    /// Dismiss the current bubble and settle back to a resting mood.
    func clearBubble(fallback: MascotMood = .idle) {
        viewModel.clearBubble(fallback: fallback)
    }
}
