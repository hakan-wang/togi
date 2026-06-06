import AppKit

@MainActor
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
        // Menu-bar / floating-mascot app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(environment: environment)

        // Bring up the mascot and its "Hey Bogi" hotkey. The fish floats even
        // before permissions are granted; capture/judge stay dormant until then.
        environment.mascot.show()
        environment.mascot.registerHeyBogiHotkey()

        // Start the core loop. Each service guards itself: capture no-ops until
        // Accessibility is trusted, the judge skips while paused/idle, and the
        // pruner only runs once per day.
        environment.capture.start()
        environment.judge.start()
        environment.retentionPruner.start()

        // Restore any persisted Supabase session; the account gate observes auth
        // changes and re-checks paid status. No-op when Supabase isn't configured.
        if let auth = environment.auth {
            Task { await auth.restoreSession() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.capture.stop()
        environment.judge.stop()
        environment.retentionPruner.stop()
    }
}
