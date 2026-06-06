import AppKit
import SwiftUI

/// Placeholder floating mascot — a borderless, always-on-top, non-activating panel.
/// Phase 6 replaces the art + adds mood states, nudges, escalation, snooze/DND.
final class MascotPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 96),
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
        contentView = NSHostingView(rootView: MascotPlaceholderView())
    }

    func show() {
        // Bottom-right of the main screen as a default resting spot.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: frame.maxX - 120, y: frame.minY + 80))
        }
        orderFrontRegardless()
    }
}

private struct MascotPlaceholderView: View {
    var body: some View {
        // Placeholder fish — real asset added later.
        Image(systemName: "fish.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 56, height: 56)
            .foregroundStyle(.orange)
            .padding(16)
            .background(.thinMaterial, in: Circle())
    }
}
