import SwiftUI
import AppKit

/// In-panel settings page (the ⚙ tab of the companion): connect Google Calendar, pause
/// capture, and sign in. Lives inside the floating panel so everything is in one place.
struct CompanionSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Calendar") {
                    if let sync = appState.calendarSync {
                        GoogleCalendarRow(sync: sync)
                    } else {
                        ProgressView()
                    }
                }

                Divider().opacity(0.4)

                section("Capture") {
                    Toggle("Pause capture", isOn: $appState.capturePaused)
                        .toggleStyle(.switch)
                    Text("Bogi reads on-screen text every few seconds, on your Mac only.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Divider().opacity(0.4)

                section("Account") {
                    LoginView(
                        signIn: { email, password in
                            try await appState.auth.signIn(email: email, password: password)
                        },
                        openWebsite: {
                            NSWorkspace.shared.open(URL(string: "https://bogi.sh/account")!)
                        }
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.headline, design: .serif)).foregroundStyle(BogiColor.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
