import AppKit
import SwiftUI

/// Borderless, frosted, draggable panel that hosts the first-run flow. Key-capable so the name and
/// North Star text fields accept input, and centered so it reads as a proper setup window even
/// though Togi is a menu-bar (accessory) app with no main window. Mirrors `CompanionPanel`.
@MainActor
final class OnboardingWindow: NSPanel {
    init(coordinator: OnboardingCoordinator) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        level = .normal
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // The brand is a bright, dreamy pastel sky. Pin the panel to the light (aqua) appearance so
        // system controls (text fields, the prominent button) render light even when the user's Mac
        // is in Dark Mode — otherwise they come back near-black and clash hard with the sky.
        appearance = NSAppearance(named: .aqua)

        let host = NSHostingView(rootView: OnboardingView(coordinator: coordinator))
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Center on screen and bring the app forward so permission and OAuth dialogs have a foreground
    /// app to anchor to.
    func present() {
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: frame.midX - 280, y: frame.midY - 320))
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
