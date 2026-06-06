import AppKit
import SwiftUI

/// Holds app-wide singletons. Grows as phases land (capture, judge, auth, …).
final class AppState: ObservableObject {
    let database: DatabaseService
    @Published var capturePaused: Bool = false

    init(database: DatabaseService) {
        self.database = database
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    private var mascot: MascotPanel?

    override init() {
        // Open (and migrate) the local database at startup. If it fails we still want the
        // app to launch in a degraded state rather than crash silently.
        let db: DatabaseService
        do {
            db = try DatabaseService(path: DatabaseService.defaultPath())
        } catch {
            NSLog("Bogi: failed to open database: \(error). Falling back to in-memory.")
            // Force-try is acceptable here: an in-memory DB creation failing is unrecoverable.
            db = try! DatabaseService(inMemory: true)
        }
        appState = AppState(database: db)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory: live in the menu bar, no dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        // Placeholder floating mascot so the running app is tangible (real art comes later).
        let mascot = MascotPanel()
        mascot.show()
        self.mascot = mascot
    }
}
