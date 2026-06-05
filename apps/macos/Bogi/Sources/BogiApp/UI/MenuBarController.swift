import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let commandBar = CommandBarWindowController()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Bogi"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Command Bar", action: #selector(showCommandBar), keyEquivalent: "k"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Bogi", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func showCommandBar() {
        commandBar.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
