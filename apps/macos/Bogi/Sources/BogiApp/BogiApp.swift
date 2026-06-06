import SwiftUI

/// Bogi — private AI accountability coach + life data bank.
///
/// Menu-bar app (accessory, no dock icon). Phase 0 wires the app shell, a menu-bar
/// entry, a Settings window, the local database, and a placeholder floating mascot.
@main
struct BogiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Togi", systemImage: "fish") {
            MenuBarContent()
                .environmentObject(appDelegate.appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}
