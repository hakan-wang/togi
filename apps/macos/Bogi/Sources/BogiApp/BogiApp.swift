import SwiftUI

enum AppMetadata {
    static let name = "Bogi"
    static let minimumMacOSMajorVersion = 14
}

@main
struct BogiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Bogi is a menu-bar / floating-mascot app (accessory activation policy);
        // the Settings scene provides the standard macOS settings window.
        Settings {
            SettingsView()
                .environmentObject(appDelegate.environment)
        }
    }
}
