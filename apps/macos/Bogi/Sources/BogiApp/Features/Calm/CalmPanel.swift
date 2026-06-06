import AppKit
import SwiftUI

/// The floating "take a breath" overlay panel: borderless, transparent, always-on-top,
/// centered on the main screen. Hosts `CalmView`. Same window-shell pattern as
/// `MascotPanel` / `CompanionPanel` — the panel is just the shell; the breathing logic
/// lives in the SwiftUI view.
@MainActor
final class CalmPanel: NSPanel {
    init<Content: View>(@ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 580),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false            // the rounded card draws its own SwiftUI shadow
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: content())
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    func show() {
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: frame.midX - 230, y: frame.midY - 290))
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func hide() { orderOut(nil) }
}
