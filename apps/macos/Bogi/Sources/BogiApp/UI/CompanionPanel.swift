import AppKit
import SwiftUI

/// Borderless, frosted, draggable panel that hosts `CompanionView` — the floating command
/// bar. It opens small and grows downward as the conversation fills, keeping its top edge
/// pinned, and never grows past a fraction of the screen. Becomes key so the chat field
/// accepts input.
@MainActor
final class CompanionPanel: NSPanel {
    private let panelWidth: CGFloat = 420
    private var didInitialSize = false

    /// The content builder receives the max height it may use and a callback to report its
    /// rendered height back to the panel for resizing.
    init<Content: View>(@ViewBuilder content: (CGFloat, @escaping (CGFloat) -> Void) -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        level = .normal
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true                    // system shadow follows the rounded card
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // The brand is light and dreamy: pin the card to a light appearance so the frosted
        // glass stays readable over any wallpaper, even with the system in dark mode.
        appearance = NSAppearance(named: .aqua)

        let report: (CGFloat) -> Void = { [weak self] height in self?.applyContentHeight(height) }
        let host = NSHostingView(rootView: content(Self.maxContentHeight(), report))
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// The card may grow to at most ~60% of the usable screen before the transcript scrolls.
    private static func maxContentHeight() -> CGFloat {
        guard let screen = NSScreen.main else { return 600 }
        return min(620, screen.visibleFrame.height * 0.6)
    }

    /// Resize to the content's height, pinning the top edge so the card grows downward.
    private func applyContentHeight(_ raw: CGFloat) {
        let height = max(120, min(raw, Self.maxContentHeight()))
        guard abs(frame.height - height) > 0.5 else { return }

        let top = frame.maxY                    // current top edge, wherever it's been dragged to
        var newFrame = frame
        newFrame.size.width = panelWidth
        newFrame.size.height = height
        newFrame.origin.y = top - height

        if didInitialSize {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: false)
            didInitialSize = true
        }
    }

    /// Anchor near the top-center of the screen, a touch below the notch, keeping the
    /// current height so growth continues from there.
    func show() {
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            setFrameTopLeftPoint(NSPoint(x: visible.midX - panelWidth / 2, y: visible.maxY - 36))
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        // Tell the hosted view to reset to a fresh, small chat with refreshed openers.
        NotificationCenter.default.post(name: .companionDidOpen, object: nil)
    }

    func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
            show()
        }
    }
}

extension Notification.Name {
    /// Posted when the companion panel is shown, so the chat can refresh its openers and refocus
    /// the input. The transcript itself persists across opens (the panel is reused).
    static let companionDidOpen = Notification.Name("companionDidOpen")
    /// Posted when the user taps "clear chat", so the chat surface wipes its transcript.
    static let companionClearChat = Notification.Name("companionClearChat")
}
