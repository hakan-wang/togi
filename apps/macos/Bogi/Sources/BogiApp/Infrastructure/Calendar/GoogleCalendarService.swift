import Foundation
import CryptoKit
import AuthenticationServices

/// Client-side Google Calendar integration using installed-app OAuth with PKCE (no client secret).
/// Tokens live ONLY in the macOS Keychain; they are never sent to any Bogi backend. The app talks
/// to the Google Calendar REST API directly.
///
/// Network code here is structured to compile and be unit-test-friendly; it does not need to run
/// during this phase. PKCE generation and token bookkeeping are isolated so they can be tested.
final class GoogleCalendarService {
    /// Keychain account under which the encoded token bundle is stored.
    static let keychainAccount = "google-calendar"

    /// OAuth + API endpoints.
    private static let authorizeEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    // Read-only: Bogi only reads your planned events (intent). Minimal scope = easier
    // Google verification and a smaller ask on the consent screen.
    private static let calendarScope = "https://www.googleapis.com/auth/calendar.events.readonly"
    private static let eventsListBase = "https://www.googleapis.com/calendar/v3/calendars/primary/events"

    private let tokenStore: KeychainTokenStore
    private let session: URLSession
    /// Custom URL scheme registered by the app for the OAuth redirect, e.g. "com.bogi.app".
    private let redirectScheme: String

    /// Holds the in-flight ASWebAuthenticationSession's presentation provider.
    private var presentationProvider: PresentationContextProvider?

    init(
        tokenStore: KeychainTokenStore = KeychainTokenStore(),
        redirectScheme: String = "com.bogi.app",
        session: URLSession = .shared
    ) {
        self.tokenStore = tokenStore
        self.redirectScheme = redirectScheme
        self.session = session
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

    enum GoogleCalendarError: Error {
        case authorizationFailed
        case missingAuthorizationCode
        case tokenExchangeFailed
        case notAuthenticated
        case requestFailed(status: Int)
    }

    /// Run the full installed-app PKCE flow: open Google's consent page, capture the redirect's
    /// authorization code, exchange it (no client secret) and persist the tokens in Keychain.
    @MainActor
    func authorize(clientId: String, presentationAnchor: ASPresentationAnchor) async throws {
        let pkce = Self.makePKCE()
        // Loopback redirect URI form: "<scheme>:/oauth2redirect" (custom scheme, installed app).
        let redirectURI = "\(redirectScheme):/oauth2redirect"

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
        guard let authURL = components.url else { throw GoogleCalendarError.authorizationFailed }

        let callbackURL = try await presentAuthSession(
            authURL: authURL,
            scheme: redirectScheme,
            anchor: presentationAnchor
        )

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
        else {
            throw GoogleCalendarError.missingAuthorizationCode
        }

        try await exchangeCode(code, clientId: clientId, verifier: pkce.verifier, redirectURI: redirectURI)
    }

    @MainActor
    private func presentAuthSession(
        authURL: URL,
        scheme: String,
        anchor: ASPresentationAnchor
    ) async throws -> URL {
        let provider = PresentationContextProvider(anchor: anchor)
        self.presentationProvider = provider
        return try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: scheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? GoogleCalendarError.authorizationFailed)
                }
            }
            authSession.presentationContextProvider = provider
            authSession.prefersEphemeralWebBrowserSession = false
            if !authSession.start() {
                continuation.resume(throwing: GoogleCalendarError.authorizationFailed)
            }
        }
    }

    // MARK: - Token exchange / refresh

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Int?
    }

    private func exchangeCode(_ code: String, clientId: String, verifier: String, redirectURI: String) async throws {
        let params = [
            "client_id": clientId,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        let response = try await postForm(Self.tokenEndpoint, params: params)
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: response) else {
            throw GoogleCalendarError.tokenExchangeFailed
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
    private func refreshAccessToken(clientId: String) async throws -> String {
        guard let bundle = loadTokens(), let refreshToken = bundle.refreshToken else {
            throw GoogleCalendarError.notAuthenticated
        }
        let params = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        let response = try await postForm(Self.tokenEndpoint, params: params)
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: response) else {
            throw GoogleCalendarError.tokenExchangeFailed
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
            throw GoogleCalendarError.requestFailed(status: http.statusCode)
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
        }
        var items: [Item]?
    }

    /// Fetch events in [start, end) from the user's primary calendar. Refreshes the access token
    /// once on a 401. `clientId` is needed for the refresh path; pass the same id used to authorize.
    func fetchEvents(start: Date, end: Date, clientId: String) async throws -> [ExternalCalendarEvent] {
        guard let bundle = loadTokens() else { throw GoogleCalendarError.notAuthenticated }
        do {
            return try await fetchEvents(start: start, end: end, accessToken: bundle.accessToken)
        } catch GoogleCalendarError.requestFailed(let status) where status == 401 {
            let refreshed = try await refreshAccessToken(clientId: clientId)
            return try await fetchEvents(start: start, end: end, accessToken: refreshed)
        }
    }

    /// Convenience overload matching the requested signature; resolves clientId from nothing and so
    /// will not auto-refresh. Prefer the `clientId:` variant where a refresh is desirable.
    func fetchEvents(start: Date, end: Date) async throws -> [ExternalCalendarEvent] {
        guard let bundle = loadTokens() else { throw GoogleCalendarError.notAuthenticated }
        return try await fetchEvents(start: start, end: end, accessToken: bundle.accessToken)
    }

    private func fetchEvents(start: Date, end: Date, accessToken: String) async throws -> [ExternalCalendarEvent] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: Self.eventsListBase)!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: start)),
            URLQueryItem(name: "timeMax", value: iso.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GoogleCalendarError.requestFailed(status: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(EventsListResponse.self, from: data)
        return (decoded.items ?? []).compactMap { item -> ExternalCalendarEvent? in
            guard let id = item.id else { return nil }
            guard let start = Self.parseEventDate(item.start, iso: iso),
                  let end = Self.parseEventDate(item.end, iso: iso) else { return nil }
            return ExternalCalendarEvent(
                source: "google",
                externalId: id,
                title: item.summary ?? "(untitled)",
                start: start,
                end: end
            )
        }
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

/// Supplies the presentation anchor (window) for ASWebAuthenticationSession.
private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
