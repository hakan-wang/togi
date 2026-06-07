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
            // Square and roomy so the voice aura can bloom past the axolotl without being
            // clipped, and a multi-line nudge bubble (maxWidth 200) still wraps cleanly.
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false                   // no boxy window-shadow ring around the mascot
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Route the view's tap through this panel's `onActivate` so the owner can swap
        // the closure at any time without rebuilding the hosting view.
        let root = MascotView(viewModel: self.viewModel, onActivate: { [weak self] in
            self?.onActivate?()
        })
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.layer?.masksToBounds = false   // let the voice aura glow past the content box
        host.clipsToBounds = false
        contentView = host
    }

    func show() {
        // Bottom-right of the main screen as a default resting spot — only on the
        // first reveal. Subsequent shows (e.g. after hide, or a nudge auto-reappear)
        // keep the position the user last dragged the mascot to.
        if !hasSetInitialPosition, let resting = Self.restingOrigin() {
            setFrameOrigin(resting)
            hasSetInitialPosition = true
        }
        orderFrontRegardless()
    }

    /// Default resting spot: bottom-right of the main screen's visible frame. `nil` when there's
    /// no main screen, so callers can fall back to a plain reveal.
    private static func restingOrigin() -> NSPoint? {
        guard let screen = NSScreen.main else { return nil }
        let frame = screen.visibleFrame
        return NSPoint(x: frame.maxX - 264, y: frame.minY + 72)
    }

    /// One-time copy shown the first time the mascot appears, right after onboarding.
    private static let introCopy =
        "Click me anytime to open up — ask me anything. I'm always learning, so I won't know much about you yet."

    /// First reveal after onboarding: place the mascot where the onboarding card was (screen
    /// centre), fly it to its bottom-right resting spot, then drop in the intro bubble. Falls back
    /// to a plain `show()` if there's no main screen, and skips the flight under Reduce Motion.
    func presentWithIntro() {
        guard let resting = Self.restingOrigin(), let screen = NSScreen.main else {
            show()
            showIntroBubble()
            return
        }
        // Mark placed so a later show() won't re-snap the mascot away from where it ends up.
        hasSetInitialPosition = true

        let visible = screen.visibleFrame
        let size = frame.size
        let start = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        setFrameOrigin(start)
        orderFrontRegardless()

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setFrameOrigin(resting)
            showIntroBubble()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.6
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrameOrigin(resting)
        }, completionHandler: { [weak self] in
            // The completion handler is delivered on the main thread, so it's safe to hop back
            // onto the main actor synchronously to show the (main-actor-isolated) bubble.
            MainActor.assumeIsolated { self?.showIntroBubble() }
        })
    }

    /// Show the intro bubble and auto-dismiss it after ~6s — but only if the user hasn't already
    /// dismissed it (via the × or by clicking the mascot), which `introActive` tells us.
    private func showIntroBubble() {
        viewModel.mood = .idle
        viewModel.escalationLevel = 0
        viewModel.bubbleText = Self.introCopy
        viewModel.introActive = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.viewModel.introActive else { return }
            self.viewModel.dismissIntro()
        }
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
