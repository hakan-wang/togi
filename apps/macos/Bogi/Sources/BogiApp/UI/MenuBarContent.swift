import SwiftUI

/// Menu-bar dropdown. Placeholder actions for Phase 0; wired up in later phases.
struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button("Open Dashboard") {}
            .disabled(true) // Phase 7

        Toggle("Pause Capture", isOn: $appState.capturePaused) // wired in Phase 1

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit Bogi") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
