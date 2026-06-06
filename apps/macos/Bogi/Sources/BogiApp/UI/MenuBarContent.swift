import SwiftUI

/// Menu-bar dropdown. Placeholder actions for Phase 0; wired up in later phases.
struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button("Open Togi") { appState.openDashboard?() }

        Button("Check in now") { appState.runJudgeNow?() }

        Button("Take a breath") { appState.startCalm?() }

        Menu("Togi vitality (demo)") {
            Button("Thriving") { appState.setVitalityDemo?(95) }
            Button("Happy") { appState.setVitalityDemo?(72) }
            Button("Flat") { appState.setVitalityDemo?(50) }
            Button("Tired") { appState.setVitalityDemo?(28) }
            Button("Not okay") { appState.setVitalityDemo?(8) }
        }

        Toggle("Pause Capture", isOn: $appState.capturePaused)

        Toggle("Show Mascot", isOn: $appState.mascotVisible)

        Toggle("Launch at Login", isOn: $appState.launchAtLogin)

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit Togi") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
