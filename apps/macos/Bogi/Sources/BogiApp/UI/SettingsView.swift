import SwiftUI

/// Settings shell with the tabs described in the plan. Feature modules fill in
/// each tab's detail during integration; the foundation provides the structure
/// and the privacy levers that already have a backing store.
struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView {
            PermissionsSettingsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            CaptureSettingsView()
                .tabItem { Label("Capture", systemImage: "dot.radiowaves.left.and.right") }
            AccountSettingsView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            CalendarsSettingsView()
                .tabItem { Label("Calendars", systemImage: "calendar") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
        .padding()
    }
}

struct PermissionsSettingsView: View {
    var body: some View {
        Form {
            Text("Accessibility permission is required to read on-screen text.")
            Text("Bogi never takes screenshots or records your screen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CaptureSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var retentionDays: Int = 14
    @State private var paused: Bool = false

    var body: some View {
        Form {
            Toggle("Pause capture", isOn: $paused)
                .onChange(of: paused) { environment.settings.setBool(.paused, $0) }
            Stepper("Raw retention: \(retentionDays) days", value: $retentionDays, in: 1...90)
                .onChange(of: retentionDays) { environment.settings.set(.rawRetentionDays, String($0)) }
            Text("Raw captures are pruned after the retention window. Summaries are kept.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            retentionDays = environment.settings.rawRetentionDays
            paused = environment.settings.isPaused
        }
    }
}

struct AccountSettingsView: View {
    var body: some View {
        Form {
            Text("Manage your subscription on the website.")
            Text("Bogi requires a paid account to log in.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CalendarsSettingsView: View {
    var body: some View {
        Form {
            Text("Connect Apple Calendar (EventKit) and Google Calendar (PKCE).")
            Text("Calendar data stays on your Mac; tokens live in the Keychain.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text(AppMetadata.name).font(.title2).bold()
            Text("Private AI accountability coach + life data bank.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
