import Foundation
import CryptoKit
import AppKit

/// Client-side Google Calendar integration using installed-app OAuth (Desktop client) with PKCE.
/// Tokens live ONLY in the macOS Keychain; they are never sent to any Bogi backend. The app talks
/// to the Google Calendar REST API directly. Two-way: it reads events from all of the user's
/// calendars and writes Bogi-created blocks back to their primary calendar.
///
/// PKCE generation and token bookkeeping are isolated so they can be unit-tested; the full browser
/// round-trip and REST calls are validated manually.
final class GoogleCalendarService {
    /// Keychain account under which the encoded token bundle is stored.
    static let keychainAccount = "google-calendar"

    /// Calendar Bogi creates its own blocks in. "primary" is the user's main calendar.
    static let writeCalendarId = "primary"

    /// OAuth + API endpoints.
    private static let authorizeEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    // Two-way sync: read+write events on all the user's calendars, plus list the calendars so we can
    // read secondary/shared ones. (`calendar.events` covers read & write of events; the calendar
    // list needs its own read scope.) These are sensitive scopes → require Google app verification.
    private static let calendarScope = [
        "https://www.googleapis.com/auth/calendar.events",
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    ].joined(separator: " ")
    private static let apiBase = "https://www.googleapis.com/calendar/v3"
    private static let calendarListEndpoint = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!

    private let tokenStore: KeychainTokenStore
    private let session: URLSession
    /// Opens the consent URL in the user's browser. Injectable for tests; defaults to the system
    /// browser (the loopback flow returns the user here via 127.0.0.1, not a custom scheme).
    private let openURL: (URL) -> Void

    init(
        tokenStore: KeychainTokenStore = KeychainTokenStore(),
        session: URLSession = .shared,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.tokenStore = tokenStore
        self.session = session
        self.openURL = openURL
    }

    // MARK: - PKCE (pure, testable)

    /// Generate a PKCE (code_verifier, code_challenge) pair. The verifier is a 64-char
    /// URL-safe random string; the challenge is base64url(SHA256(verifier)) per RFC 7636 (S256).
    static func makePKCE() -> (verifier: String, challenge: String) {
        let verifier = randomCodeVerifier(length: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = base64URLEncode(Data(digest))
        return (verifier, challenge)
    }

    private static func randomCodeVerifier(length: Int) -> String {
        // Unreserved characters allowed in a PKCE verifier (RFC 7636 §4.1).
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Token bundle persistence

    private struct TokenBundle: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
    }

    private func loadTokens() -> TokenBundle? {
        guard let data = tokenStore.read(account: Self.keychainAccount) else { return nil }
        return try? JSONDecoder().decode(TokenBundle.self, from: data)
    }

    private func storeTokens(_ bundle: TokenBundle) {
        guard let data = try? JSONEncoder().encode(bundle) else { return }
        tokenStore.save(data, account: Self.keychainAccount)
    }

    func signOut() {
        tokenStore.delete(account: Self.keychainAccount)
    }

    // MARK: - Authorization (installed-app PKCE)

    enum GoogleCalendarError: LocalizedError {
        case authorizationFailed
        case missingAuthorizationCode
        case tokenExchangeFailed(detail: String)
        case notAuthenticated
        case requestFailed(status: Int, detail: String)
        case authorizationTimedOut

        var errorDescription: String? {
            switch self {
            case .authorizationFailed:
                return "Google authorization failed."
            case .missingAuthorizationCode:
                return "Google didn't return an authorization code."
            case .tokenExchangeFailed(let detail):
                return "Token exchange failed: \(detail)"
            case .notAuthenticated:
                return "Not connected to Google Calendar."
            case .requestFailed(let status, let detail):
                return "Google returned HTTP \(status): \(detail)"
            case .authorizationTimedOut:
                return "Google sign-in timed out. Please try connecting again."
            }
        }
    }

    /// Run the full installed-app PKCE flow for a Desktop OAuth client using Google's supported
    /// loopback redirect: start a local 127.0.0.1 listener, open Google's consent page in the
    /// browser, capture the redirect's authorization code, exchange it and persist tokens in
    /// Keychain. (Custom URI schemes are no longer supported by Google.)
    @MainActor
    func authorize(clientId: String, clientSecret: String, timeout: TimeInterval = 300) async throws {
        let pkce = Self.makePKCE()

        let listener = try LoopbackOAuthListener()
        try await listener.start()
        defer { listener.cancel() }
        let redirectURI = "http://\(LoopbackOAuthListener.host):\(listener.port)/oauth2redirect"

        var components = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.calendarScope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = components.url else {
            throw NSError(domain: "BogiGoogleAuth", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "couldn't build the Google auth URL"])
        }

        openURL(authURL)

        // Race the browser redirect against a timeout so an abandoned consent screen doesn't hang
        // the "Connecting…" state forever. Whichever finishes first wins; the loser is cancelled.
        let callbackURL = try await withThrowingTaskGroup(of: URL.self) { group -> URL in
            group.addTask { try await listener.waitForCallback() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw GoogleCalendarError.authorizationTimedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw GoogleCalendarError.authorizationFailed
            }
            return first
        }
        let callbackItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems

        if let oauthError = callbackItems?.first(where: { $0.name == "error" })?.value {
            throw GoogleCalendarError.tokenExchangeFailed(detail: "Google denied the request: \(oauthError)")
        }
        guard let code = callbackItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleCalendarError.missingAuthorizationCode
        }

        try await exchangeCode(code, clientId: clientId, clientSecret: clientSecret, verifier: pkce.verifier, redirectURI: redirectURI)
    }

    // MARK: - Token exchange / refresh

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Int?
    }

    private func exchangeCode(_ code: String, clientId: String, clientSecret: String, verifier: String, redirectURI: String) async throws {
        var params = [
            "client_id": clientId,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        // Desktop OAuth clients require the client_secret (non-confidential for public native apps).
        if !clientSecret.isEmpty { params["client_secret"] = clientSecret }
        let response = try await postForm(Self.tokenEndpoint, params: params)
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: response) else {
            throw GoogleCalendarError.tokenExchangeFailed(detail: String(data: response, encoding: .utf8) ?? "<undecodable>")
        }
        storeTokens(TokenBundle(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: decoded.expires_in.map { Date().addingTimeInterval(Double($0)) }
        ))
    }

    /// Refresh the access token using the stored refresh token. Requires `clientId` to be supplied
    /// by the caller/integration layer (kept out of this file to avoid embedding config).
    @discardableResult
    private func refreshAccessToken(clientId: String, clientSecret: String) async throws -> String {
        guard let bundle = loadTokens(), let refreshToken = bundle.refreshToken else {
            throw GoogleCalendarError.notAuthenticated
        }
        var params = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        // Desktop OAuth clients require the client_secret on refresh too.
        if !clientSecret.isEmpty { params["client_secret"] = clientSecret }
        let response = try await postForm(Self.tokenEndpoint, params: params)
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: response) else {
            throw GoogleCalendarError.tokenExchangeFailed(detail: String(data: response, encoding: .utf8) ?? "<undecodable>")
        }
        let updated = TokenBundle(
            accessToken: decoded.access_token,
            // Google may omit the refresh token on refresh; keep the prior one.
            refreshToken: decoded.refresh_token ?? bundle.refreshToken,
            expiresAt: decoded.expires_in.map { Date().addingTimeInterval(Double($0)) }
        )
        storeTokens(updated)
        return updated.accessToken
    }

    private func postForm(_ url: URL, params: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = encodeForm(params).data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw GoogleCalendarError.requestFailed(status: http.statusCode, detail: body)
        }
        return data
    }

    private func encodeForm(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    // MARK: - Authorized requests (auto-refresh on 401)

    /// Run an authorized API call with the stored access token, refreshing once and retrying on a
    /// single 401. `body` receives a valid bearer token. Throws `notAuthenticated` if not connected.
    private func withFreshToken<T>(
        clientId: String, clientSecret: String,
        _ body: (String) async throws -> T
    ) async throws -> T {
        guard let bundle = loadTokens() else { throw GoogleCalendarError.notAuthenticated }
        do {
            return try await body(bundle.accessToken)
        } catch GoogleCalendarError.requestFailed(let status, _) where status == 401 {
            let refreshed = try await refreshAccessToken(clientId: clientId, clientSecret: clientSecret)
            return try await body(refreshed)
        }
    }

    /// Issue an authorized request (default GET) and return the body, mapping non-2xx to
    /// `requestFailed` so `withFreshToken` can catch 401s.
    private func authorizedData(
        _ url: URL, method: String = "GET", accessToken: String, jsonBody: [String: Any]? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? "<no body>"
            throw GoogleCalendarError.requestFailed(status: http.statusCode, detail: detail)
        }
        return data
    }

    // MARK: - Events API

    private struct EventsListResponse: Decodable {
        struct Item: Decodable {
            struct DateTime: Decodable {
                var dateTime: String?
                var date: String?
            }
            var id: String?
            var summary: String?
            var start: DateTime?
            var end: DateTime?
            var status: String?     // "cancelled" for deleted instances we should skip
        }
        var items: [Item]?
        var nextPageToken: String?
    }

    private struct CalendarListResponse: Decodable {
        struct Item: Decodable { var id: String? }
        var items: [Item]?
    }

    private struct CreatedEventResponse: Decodable { var id: String? }

    /// Fetch events in [start, end) from ALL of the user's calendars, following pagination.
    /// Refreshes the access token once on a 401. Pass the same clientId/secret used to authorize.
    func fetchEvents(start: Date, end: Date, clientId: String, clientSecret: String) async throws -> [ExternalCalendarEvent] {
        try await withFreshToken(clientId: clientId, clientSecret: clientSecret) { token in
            var all: [ExternalCalendarEvent] = []
            for calendarId in try await self.calendarIds(accessToken: token) {
                all += try await self.events(inCalendar: calendarId, start: start, end: end, accessToken: token)
            }
            return all
        }
    }

    /// Convenience overload that reads the primary calendar only and does not auto-refresh.
    func fetchEvents(start: Date, end: Date) async throws -> [ExternalCalendarEvent] {
        guard let bundle = loadTokens() else { throw GoogleCalendarError.notAuthenticated }
        return try await events(inCalendar: "primary", start: start, end: end, accessToken: bundle.accessToken)
    }

    /// IDs of every calendar in the user's list (primary + secondary + shared).
    private func calendarIds(accessToken: String) async throws -> [String] {
        let data = try await authorizedData(Self.calendarListEndpoint, accessToken: accessToken)
        let decoded = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        let ids = (decoded.items ?? []).compactMap { $0.id }
        return ids.isEmpty ? ["primary"] : ids
    }

    /// Page through one calendar's events in [start, end). `singleEvents=true` expands recurrences.
    private func events(inCalendar calendarId: String, start: Date, end: Date, accessToken: String) async throws -> [ExternalCalendarEvent] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var results: [ExternalCalendarEvent] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "\(Self.apiBase)/calendars/\(Self.encodePathSegment(calendarId))/events")!
            var query = [
                URLQueryItem(name: "timeMin", value: iso.string(from: start)),
                URLQueryItem(name: "timeMax", value: iso.string(from: end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "2500")
            ]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = query

            let data = try await authorizedData(components.url!, accessToken: accessToken)
            let decoded = try JSONDecoder().decode(EventsListResponse.self, from: data)

            for item in decoded.items ?? [] {
                guard item.status != "cancelled", let id = item.id,
                      let s = Self.parseEventDate(item.start, iso: iso),
                      let e = Self.parseEventDate(item.end, iso: iso) else { continue }
                results.append(ExternalCalendarEvent(
                    source: "google",
                    externalId: id,
                    title: item.summary ?? "(untitled)",
                    start: s,
                    end: e,
                    calendarId: calendarId
                ))
            }
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        return results
    }

    // MARK: - Writes (Bogi-created blocks → Google)

    /// Create an event for a Bogi-created block on its primary calendar. Returns the new event id.
    func createEvent(title: String, start: Date, end: Date, clientId: String, clientSecret: String) async throws -> String {
        try await withFreshToken(clientId: clientId, clientSecret: clientSecret) { token in
            let url = URL(string: "\(Self.apiBase)/calendars/\(Self.writeCalendarId)/events")!
            let data = try await self.authorizedData(url, method: "POST", accessToken: token,
                                                     jsonBody: Self.eventBody(title: title, start: start, end: end))
            guard let id = (try? JSONDecoder().decode(CreatedEventResponse.self, from: data))?.id else {
                throw GoogleCalendarError.requestFailed(status: 200, detail: "Google didn't return an event id")
            }
            return id
        }
    }

    /// Update an existing Google event (title/time) for a Bogi-created block.
    func updateEvent(calendarId: String, eventId: String, title: String, start: Date, end: Date, clientId: String, clientSecret: String) async throws {
        try await withFreshToken(clientId: clientId, clientSecret: clientSecret) { token in
            let url = URL(string: "\(Self.apiBase)/calendars/\(Self.encodePathSegment(calendarId))/events/\(Self.encodePathSegment(eventId))")!
            _ = try await self.authorizedData(url, method: "PATCH", accessToken: token,
                                              jsonBody: Self.eventBody(title: title, start: start, end: end))
        }
    }

    private static func eventBody(title: String, start: Date, end: Date) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return [
            "summary": title,
            "start": ["dateTime": iso.string(from: start)],
            "end": ["dateTime": iso.string(from: end)]
        ]
    }

    /// Percent-encode a single URL path segment (calendar ids / event ids can contain `@`, `#`, …).
    private static func encodePathSegment(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? segment
    }

    private static func parseEventDate(_ dt: EventsListResponse.Item.DateTime?, iso: ISO8601DateFormatter) -> Date? {
        guard let dt else { return nil }
        if let dateTime = dt.dateTime, let parsed = iso.date(from: dateTime) {
            return parsed
        }
        if let date = dt.date {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone.current
            return df.date(from: date)
        }
        return nil
    }
}
