import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment: AppEnvironment
    private var menuBarController: MenuBarController?

    override init() {
        // Build the shared environment (database + services) before the app
        // finishes launching so SwiftUI scenes can observe it.
        self.environment = AppEnvironment.live()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(environment: environment)
    }
}
