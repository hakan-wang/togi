import AppKit
import SwiftUI

/// Holds app-wide singletons. Grows as phases land (judge, auth, …).
final class AppState: ObservableObject {
    let database: DatabaseService
    let capture: CaptureController
    private let settings: SettingsStore

    @Published var capturePaused: Bool {
        didSet {
            capture.isPaused = capturePaused
            settings.setBool("paused", capturePaused)
        }
    }

    init(database: DatabaseService) {
        self.database = database
        let settings = SettingsStore(database: database)
        self.settings = settings

        let excludes = CaptureExcludes.makeDefault(
            userApps: settings.stringArray("excluded_apps"),
            userDomains: settings.stringArray("excluded_domains")
        )
        self.capture = CaptureController(
            provider: AccessibilityCaptureService(),
            store: ObservationStore(database: database),
            excludes: excludes,
            pruner: RetentionPruner(database: database),
            settings: settings
        )

        let paused = settings.bool("paused", default: false)
        self.capturePaused = paused
        capture.isPaused = paused
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    private var mascot: MascotPanel?

    override init() {
        let db: DatabaseService
        do {
            db = try DatabaseService(path: DatabaseService.defaultPath())
        } catch {
            NSLog("Bogi: failed to open database: \(error). Falling back to in-memory.")
            db = try! DatabaseService(inMemory: true)
        }
        appState = AppState(database: db)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Ask for Accessibility up front (Phase 4 moves this into a proper onboarding primer).
        if appState.capture.permissionState != .granted {
            appState.capture.requestPermission()
        }
        appState.capture.start()

        let mascot = MascotPanel()
        mascot.show()
        self.mascot = mascot
    }
}
