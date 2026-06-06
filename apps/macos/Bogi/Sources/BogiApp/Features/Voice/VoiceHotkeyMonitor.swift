import AppKit

/// Global "tap Control to talk" hotkey. A clean tap of the Control key on its own — pressed and
/// released with no other key or modifier in between — fires `onTrigger`. Control used as part of
/// a real shortcut (Control-C, Control-click, Control-arrow, ⌃⌘…) is ignored, so the hotkey never
/// steals normal shortcuts.
///
/// The global monitor needs Accessibility permission, which Togi already requests for its capture
/// loop; the local monitor covers the case where Togi itself is the focused app regardless.
@MainActor
final class VoiceHotkeyMonitor {
    /// Fired on a clean Control tap. Wired by the host to start/stop a voice exchange.
    var onTrigger: () -> Void = {}

    private var monitors: [Any] = []
    private var controlDown = false
    private var cleanTap = false

    func start() {
        // NSEvent monitors are delivered on the main thread, so it is safe to assume isolation.
        let onFlags: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event) }
        }
        let onKey: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.handleKeyDown() }
        }

        addMonitor(.flagsChanged, onFlags)
        addMonitor(.keyDown, onKey)
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        controlDown = false
        cleanTap = false
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

        if controlNow, !controlDown {
            // Control just went down — arm a tap only if it's Control on its own.
            controlDown = true
            cleanTap = onlyControl
        } else if !controlNow, controlDown {
            // Control just came up — a tap counts only if it stayed clean throughout.
            controlDown = false
            if cleanTap {
                cleanTap = false
                onTrigger()
            }
        } else if controlNow, !onlyControl {
            // Another modifier joined while Control was held → no longer a clean tap.
            cleanTap = false
        }
    }

    private func handleKeyDown() {
        // A normal key pressed while Control is held → it's a shortcut, not a tap.
        if controlDown { cleanTap = false }
    }
}
