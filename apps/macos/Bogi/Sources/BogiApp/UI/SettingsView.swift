import SwiftUI
import AppKit

/// Settings shell with the tabs the spec calls for. The Account tab hosts the real login;
/// the rest are placeholders filled in by their owning phase.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            PlaceholderTab(title: "Permissions", note: "Accessibility, Calendars, Microphone — Phase 1/4")
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            PlaceholderTab(title: "Capture", note: "Pause, app/domain excludes, retention — Phase 1")
                .tabItem { Label("Capture", systemImage: "eye") }

            CalendarsSettingsView()
                .tabItem { Label("Calendars", systemImage: "calendar") }

            LoginView(
                signIn: { email, password in try await appState.auth.signIn(email: email, password: password) },
                openWebsite: { NSWorkspace.shared.open(WebsiteConfig.accountURL) }
            )
            .tabItem { Label("Account", systemImage: "person.crop.circle") }

            PlaceholderTab(title: "About", note: "Version, updates — Phase 8")
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }
}

private struct PlaceholderTab: View {
    let title: String
    let note: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.title2).bold()
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
