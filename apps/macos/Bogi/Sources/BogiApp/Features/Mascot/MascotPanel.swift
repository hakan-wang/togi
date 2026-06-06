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

    init(viewModel: MascotViewModel? = nil) {
        self.viewModel = viewModel ?? MascotViewModel()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 172, height: 184),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Route the view's tap through this panel's `onActivate` so the owner can swap
        // the closure at any time without rebuilding the hosting view.
        let root = MascotView(viewModel: self.viewModel, onActivate: { [weak self] in
            self?.onActivate?()
        })
        contentView = NSHostingView(rootView: root)
    }

    func show() {
        // Bottom-right of the main screen as a default resting spot.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: frame.maxX - 196, y: frame.minY + 72))
        }
        orderFrontRegardless()
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
