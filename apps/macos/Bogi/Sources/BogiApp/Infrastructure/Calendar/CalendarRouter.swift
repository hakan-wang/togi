import Foundation
import AppKit
import AuthenticationServices

/// Decides where a voice-scheduled event lands: straight to Google Calendar (direct API) when the
/// user has connected their Google account, otherwise to Apple Calendar via EventKit. Undo routes
/// back to whichever backend created the event, so the two never get crossed.
///
/// Configuration (env var → settings table):
/// - Google OAuth client id: `GOOGLE_CLIENT_ID` / `google_client_id`. Without it, Google is never
///   used and everything falls to Apple Calendar — nothing breaks, it just won't sync to Google.
/// - Redirect scheme (must match the OAuth client): `GOOGLE_REDIRECT_SCHEME` / `google_redirect_scheme`,
///   default `com.bogi.app`.
final class CalendarRouter {
    enum Source: String, Equatable {
        case google
        case apple
    }

    struct Booked: Equatable {
        let id: String
        let source: Source
    }

    enum RouterError: Error {
        case appleNotAuthorized
        case appleSaveFailed
        case googleNotConfigured
    }

    private let eventKit: EventKitService
    private let settings: SettingsStore

    init(eventKit: EventKitService, settings: SettingsStore) {
        self.eventKit = eventKit
        self.settings = settings
    }

    // MARK: - Config

    private static func configured(_ env: String, _ key: String, in settings: SettingsStore) -> String? {
        if let value = ProcessInfo.processInfo.environment[env], !value.isEmpty { return value }
        if let stored = settings.string(key), !stored.isEmpty { return stored }
        return nil
    }

    private var googleClientId: String? {
        CalendarRouter.configured("GOOGLE_CLIENT_ID", "google_client_id", in: settings)
    }

    /// Build a Google service that reflects the current redirect-scheme setting. The Keychain is the
    /// source of truth for tokens, so a fresh instance is cheap and avoids caching a stale scheme.
    private func makeGoogle() -> GoogleCalendarService {
        let scheme = CalendarRouter.configured("GOOGLE_REDIRECT_SCHEME", "google_redirect_scheme", in: settings)
        return GoogleCalendarService(redirectScheme: scheme ?? "com.bogi.app")
    }

    /// True when Togi should book straight to Google: a client id is configured AND a token is in
    /// the Keychain (the user has actually connected their account).
    var googleConnected: Bool {
        googleClientId != nil && makeGoogle().isAuthenticated
    }

    /// True when a client id is present but the user hasn't signed in yet (drives the Settings UI).
    var googleConfiguredButNotConnected: Bool {
        googleClientId != nil && !makeGoogle().isAuthenticated
    }

    // MARK: - Apple permission (only relevant on the fallback path)

    func appleNeedsPermission() -> Bool { eventKit.authorizationStatus() == .notDetermined }
    func appleAuthorized() -> Bool { eventKit.authorizationStatus() == .granted }
    func requestAppleAccess() async -> Bool { await eventKit.requestAccess() }

    // MARK: - Booking

    /// Book an event. Prefers Google when connected; if the Google call fails, falls back to Apple
    /// (when authorized) so the event still lands somewhere rather than silently vanishing.
    func book(title: String, start: Date, end: Date, notes: String?) async throws -> Booked {
        if googleConnected, let clientId = googleClientId {
            do {
                let id = try await makeGoogle().createEvent(
                    title: title, start: start, end: end, notes: notes, clientId: clientId
                )
                return Booked(id: id, source: .google)
            } catch {
                // Google failed (network, revoked token). Fall back to Apple if we can; otherwise
                // surface the failure so the user isn't told "done" when nothing was saved.
                guard appleAuthorized() else { throw error }
            }
        }

        guard appleAuthorized() else { throw RouterError.appleNotAuthorized }
        guard let id = eventKit.createEvent(title: title, start: start, end: end, notes: notes) else {
            throw RouterError.appleSaveFailed
        }
        return Booked(id: id, source: .apple)
    }

    /// Remove a previously-booked event from whichever calendar created it. Best-effort.
    func delete(_ booked: Booked) async {
        switch booked.source {
        case .apple:
            _ = eventKit.deleteEvent(identifier: booked.id)
        case .google:
            guard let clientId = googleClientId else { return }
            _ = try? await makeGoogle().deleteEvent(id: booked.id, clientId: clientId)
        }
    }

    // MARK: - Google connect / disconnect (Settings UI)

    /// Run Google's sign-in consent flow and store the tokens in the Keychain. Must be called on the
    /// main actor because it presents a web auth sheet.
    @MainActor
    func connectGoogle() async throws {
        guard let clientId = googleClientId else { throw RouterError.googleNotConfigured }
        let anchor: ASPresentationAnchor = NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        try await makeGoogle().authorize(clientId: clientId, presentationAnchor: anchor)
    }

    func disconnectGoogle() {
        makeGoogle().signOut()
    }
}
