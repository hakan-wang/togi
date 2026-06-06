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

            CalendarsSettingsTab(settings: appState.settings, calendar: appState.calendar)
                .tabItem { Label("Calendars", systemImage: "calendar") }

            LoginView(
                signIn: { email, password in try await appState.auth.signIn(email: email, password: password) },
                openWebsite: { NSWorkspace.shared.open(URL(string: "https://bogi.sh/account")!) }
            )
            .tabItem { Label("Account", systemImage: "person.crop.circle") }

            VoiceSettingsTab(settings: appState.settings)
                .tabItem { Label("Voice", systemImage: "waveform") }

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

/// Calendars tab: connect Google Calendar so voice-scheduled events sync straight to Google.
/// Without it, Togi falls back to Apple Calendar (whatever account is connected in macOS Calendar),
/// so scheduling still works — it just won't go to Google directly.
private struct CalendarsSettingsTab: View {
    let settings: SettingsStore
    let calendar: CalendarRouter

    @State private var clientId = ""
    @State private var redirectScheme = ""
    @State private var saved = false
    @State private var connected = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Google Calendar") {
                if connected {
                    Label("connected to google calendar", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("voice events go straight to your google calendar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("disconnect") {
                        calendar.disconnectGoogle()
                        refresh()
                    }
                } else {
                    SecureField("OAuth client id", text: $clientId)
                    TextField("redirect scheme", text: $redirectScheme, prompt: Text("com.bogi.app"))
                    Text("paste the client id from your google cloud oauth client (ios/macos type). leave the scheme on its default unless your client uses a different one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(saved ? "saved" : "save") { persist(); saved = true }
                        Button(working ? "connecting…" : "connect google calendar") { connect() }
                            .disabled(working || clientId.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Text("no google account connected? togi books to apple calendar instead. add a google account in the mac's calendar app and those events sync to google too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear {
            clientId = settings.string("google_client_id") ?? ""
            redirectScheme = settings.string("google_redirect_scheme") ?? ""
            refresh()
        }
        .onChange(of: clientId) { _, _ in saved = false }
        .onChange(of: redirectScheme) { _, _ in saved = false }
    }

    private func refresh() { connected = calendar.googleConnected }

    private func persist() {
        settings.set("google_client_id", clientId.trimmingCharacters(in: .whitespacesAndNewlines))
        let scheme = redirectScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.set("google_redirect_scheme", scheme.isEmpty ? nil : scheme)
    }

    private func connect() {
        working = true
        error = nil
        persist()   // so the router authorizes with the id/scheme currently in the fields
        Task {
            do {
                try await calendar.connectGoogle()
            } catch {
                self.error = "couldn't connect: \(error.localizedDescription)"
            }
            working = false
            refresh()
        }
    }
}

/// Voice tab: paste an ElevenLabs key for a crisp spoken voice. Stored in the settings table,
/// which `VoiceOutput` reads; empty falls back to the built-in macOS voice.
private struct VoiceSettingsTab: View {
    let settings: SettingsStore
    @State private var apiKey = ""
    @State private var voiceId = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("ElevenLabs voice (optional)") {
                SecureField("API key", text: $apiKey)
                TextField("Voice ID", text: $voiceId, prompt: Text("21m00Tcm4TlvDq8ikWAM (Rachel)"))
                Text("paste a key for a clear, natural voice. leave empty to use the built-in mac voice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(saved ? "saved" : "save") {
                settings.set("elevenlabs_api_key", apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                settings.set("elevenlabs_voice_id", voiceId.trimmingCharacters(in: .whitespacesAndNewlines))
                saved = true
            }
        }
        .padding()
        .onAppear {
            apiKey = settings.string("elevenlabs_api_key") ?? ""
            voiceId = settings.string("elevenlabs_voice_id") ?? ""
        }
        .onChange(of: apiKey) { _, _ in saved = false }
        .onChange(of: voiceId) { _, _ in saved = false }
    }
}
