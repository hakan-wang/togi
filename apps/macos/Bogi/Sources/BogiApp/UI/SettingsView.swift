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

            PlaceholderTab(title: "Calendars", note: "Apple (EventKit) + Google (PKCE) — Phase 4")
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
