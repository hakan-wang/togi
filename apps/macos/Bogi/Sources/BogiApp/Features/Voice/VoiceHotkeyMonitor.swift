import AppKit

/// Global "tap Control to talk" hotkey. Tapping Control on its own (press then release, with no
/// other key or modifier and no click in between) fires `onToggle` — start a hands-free
/// conversation, or end one already running. Pressing Escape fires `onEscape` to bail out.
///
/// A real Control shortcut (Control-C, ⌃⌘…, Control-click) never triggers a toggle: the moment
/// another key, modifier, or mouse button joins, the in-progress tap is disarmed.
///
/// The global case needs Accessibility permission (the same one Togi's capture loop requests);
/// the local monitor covers the case where Togi itself is focused.
@MainActor
final class VoiceHotkeyMonitor {
    /// Control tapped on its own: toggle the conversation on/off.
    var onToggle: () -> Void = {}
    /// Escape pressed: cancel a conversation in progress.
    var onEscape: () -> Void = {}

    private var monitors: [Any] = []
    private var controlHeld = false   // Control physically down
    private var armed = false         // a clean Control tap is in progress (nothing else has joined)

    func start() {
        // NSEvent monitors are delivered on the main thread, so it's safe to assume isolation.
        let onFlags: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event) }
        }
        let onKey: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handleKeyDown(event) }
        }
        let onMouse: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.disarm() }
        }
        addMonitor(.flagsChanged, onFlags)
        addMonitor(.keyDown, onKey)
        addMonitor([.leftMouseDown, .rightMouseDown], onMouse)
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        controlHeld = false
        armed = false
    }

    private func addMonitor(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags
        let controlNow = flags.contains(.control)
        let onlyControl = controlNow
            && !flags.contains(.command)
            && !flags.contains(.option)
            && !flags.contains(.shift)

        if controlNow, !controlHeld {
            // Control went down — arm a tap only if it's Control on its own.
            controlHeld = true
            armed = onlyControl
        } else if !controlNow, controlHeld {
            // Control released — a clean, lone tap fires the toggle.
            controlHeld = false
            if armed { armed = false; onToggle() }
        } else if controlNow, !onlyControl {
            // Another modifier joined → it's a chord, not a tap.
            armed = false
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 {            // Escape
            onEscape()
            return
        }
        // A normal key while Control is held → it's a shortcut, not a tap.
        if controlHeld { armed = false }
    }

    private func disarm() {
        // A click while Control is held (e.g. Control-click) is not a talk gesture.
        if controlHeld { armed = false }
    }
}
