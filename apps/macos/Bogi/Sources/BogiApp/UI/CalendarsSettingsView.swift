import SwiftUI
import AppKit
import AuthenticationServices

/// Settings → Calendars. Google only for now: connect, sync, disconnect.
struct CalendarsSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let sync = appState.calendarSync {
                GoogleCalendarRow(sync: sync)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            Spacer()
        }
        .padding(20)
    }
}

struct GoogleCalendarRow: View {
    @ObservedObject var sync: CalendarSyncCoordinator
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Google Calendar")
                .font(.system(.title3, design: .serif))

            if sync.googleConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let last = sync.lastSync {
                    Text("Last synced \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(working ? "Syncing…" : "Sync now") {
                        Task { working = true; await sync.syncNow(); working = false }
                    }
                    .disabled(working)
                    Button("Disconnect", role: .destructive) { sync.disconnectGoogle() }
                }
            } else {
                Text("Connect Google Calendar so Bogi knows what you planned, and can hold you to it.")
                    .font(.callout).foregroundStyle(.secondary)
                Button(working ? "Connecting…" : "Connect Google Calendar") {
                    Task {
                        working = true
                        let anchor: ASPresentationAnchor = NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
                        await sync.connectGoogle(anchor: anchor)
                        working = false
                    }
                }
                .disabled(working)
            }

            if let error = sync.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
