import AppKit
import SwiftUI

/// Borderless, frosted, draggable panel that hosts `CompanionView` — the Goldfish-style
/// floating surface. Becomes key so the chat text field accepts input.
@MainActor
final class CompanionPanel: NSPanel {
    init<Content: View>(@ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.borderless, .resizable],
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

        let host = NSHostingView(rootView: content())
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Anchor near the top-center of the screen (like the reference), a touch below the notch.
    func show() {
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            setFrameTopLeftPoint(NSPoint(x: frame.midX - 210, y: frame.maxY - 36))
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
            show()
        }
    }
}
