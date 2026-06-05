import SwiftUI

enum AppMetadata {
    static let name = "Bogi"
    static let minimumMacOSMajorVersion = 14
}

@main
struct BogiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
