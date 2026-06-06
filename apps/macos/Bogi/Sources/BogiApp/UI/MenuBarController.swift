import AppKit

/// The `NSStatusItem` menu-bar entry: open dashboard, pause/resume capture,
/// settings, quit. Feature modules extend this during integration (e.g. the
/// dashboard/planner windows) — for the foundation it provides the shell.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐟"
        statusItem.button?.toolTip = "Bogi"
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        let pauseTitle = environment.settings.isPaused ? "Resume Capture" : "Pause Capture"
        menu.addItem(NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Bogi", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    @objc private func openDashboard() {
        // Wired to BankViews during integration (Phase 7).
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePause() {
        let now = environment.settings.isPaused
        environment.settings.setBool(.paused, !now)
        rebuildMenu()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
