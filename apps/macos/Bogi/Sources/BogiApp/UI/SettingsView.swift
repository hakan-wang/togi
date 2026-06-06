import SwiftUI

/// Settings shell with the tabs the spec calls for. Each tab is a placeholder in Phase 0
/// and gets filled in by its owning phase.
struct SettingsView: View {
    var body: some View {
        TabView {
            PlaceholderTab(title: "Permissions", note: "Accessibility, Calendars, Microphone — Phase 1/4")
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            PlaceholderTab(title: "Capture", note: "Pause, app/domain excludes, retention — Phase 1")
                .tabItem { Label("Capture", systemImage: "eye") }

            PlaceholderTab(title: "Calendars", note: "Apple (EventKit) + Google (PKCE) — Phase 4")
                .tabItem { Label("Calendars", systemImage: "calendar") }

            PlaceholderTab(title: "Account", note: "Supabase login + paid status — Phase 3")
                .tabItem { Label("Account", systemImage: "person.crop.circle") }

            PlaceholderTab(title: "About", note: "Version, updates — Phase 8")
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 320)
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
