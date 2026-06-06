import Foundation
import CryptoKit
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

// Google Calendar via client-side OAuth (installed-app PKCE, NO client secret).
// Tokens live in the macOS Keychain; the app calls the Google Calendar API
// directly and refreshes locally. No tokens or calendar data ever reach the
// backend. The security-sensitive, hard-to-test bits — PKCE generation and the
// "is this token still usable?" decision — are isolated as pure helpers below.

// MARK: - PKCE (pure, testable)

/// A PKCE verifier/challenge pair (RFC 7636). `method` is always `S256`.
struct PKCEPair: Equatable {
    let verifier: String
    let challenge: String
    let method = "S256"

    init(verifier: String, challenge: String) {
        self.verifier = verifier
        self.challenge = challenge
    }
}

enum PKCE {
    /// base64url-encode without padding (RFC 7636 §3 / RFC 4648 §5).
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Build a code verifier from raw random bytes (43–128 chars after encoding).
    static func makeVerifier(from randomBytes: [UInt8]) -> String {
        base64URLEncode(Data(randomBytes))
    }

    /// The S256 code challenge for a verifier: base64url(SHA256(ascii(verifier))).
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    /// Generate a fresh PKCE pair. `randomBytes` is injectable for tests; the
    /// default uses 32 cryptographically-random bytes.
    static func generate(randomBytes: () -> [UInt8] = { PKCE.secureRandomBytes(32) }) -> PKCEPair {
        let verifier = makeVerifier(from: randomBytes())
        return PKCEPair(verifier: verifier, challenge: challenge(for: verifier))
    }

    static func secureRandomBytes(_ count: Int = 32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return bytes
    }
}

// MARK: - OAuth token + refresh decision (pure, testable)

struct OAuthToken: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String?

    init(accessToken: String, refreshToken: String?, expiresAt: Date, scope: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    /// Build a token from Google's `expires_in` (seconds-from-now) response.
    init(accessToken: String, refreshToken: String?, expiresIn: TimeInterval, now: Date, scope: String? = nil) {
        self.init(accessToken: accessToken, refreshToken: refreshToken,
                  expiresAt: now.addingTimeInterval(expiresIn), scope: scope)
    }
}

enum TokenRefreshDecision: Equatable {
    /// Token is valid; use it as-is.
    case usable
    /// Token is expired/expiring but we hold a refresh token — refresh locally.
    case refresh
    /// No token, or expired with no refresh token — full re-auth required.
    case reauthenticate
}

enum TokenLogic {
    /// Decide what to do with a stored token before making an API call.
    /// `leeway` refreshes slightly early to avoid mid-request expiry.
    static func decision(for token: OAuthToken?, now: Date, leeway: TimeInterval = 60) -> TokenRefreshDecision {
        guard let token else { return .reauthenticate }
        if now < token.expiresAt.addingTimeInterval(-leeway) {
            return .usable
        }
        return token.refreshToken != nil ? .refresh : .reauthenticate
    }

    /// Decide what to do after the API returns an HTTP status. A 401 means the
    /// access token was rejected: refresh if possible, else re-auth.
    static func decision(forStatus status: Int, token: OAuthToken?) -> TokenRefreshDecision {
        guard status == 401 else { return .usable }
        return (token?.refreshToken != nil) ? .refresh : .reauthenticate
    }
}

// MARK: - Token storage (Keychain, mockable)

/// Abstracts where OAuth tokens are persisted so the service is testable without
/// touching the real Keychain.
protocol TokenStore {
    func load(account: String) throws -> OAuthToken?
    func save(_ token: OAuthToken, account: String) throws
    func delete(account: String) throws
}

/// Stores OAuth tokens as a JSON blob in the macOS Keychain (generic password).
/// Tokens never leave the device and are never sent to the backend.
final class KeychainTokenStore: TokenStore {
    private let service: String

    init(service: String = "ai.bogi.googlecalendar") {
        self.service = service
    }

    func load(account: String) throws -> OAuthToken? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CalendarSourceError.invalidResponse
        }
        return try JSONDecoder().decode(OAuthToken.self, from: data)
    }

    func save(_ token: OAuthToken, account: String) throws {
        let data = try JSONEncoder().encode(token)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw CalendarSourceError.invalidResponse }
        } else if status != errSecSuccess {
            throw CalendarSourceError.invalidResponse
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CalendarSourceError.invalidResponse
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

// MARK: - OAuth configuration + URL building (pure parts)

struct GoogleOAuthConfig: Equatable {
    var clientId: String
    /// Loopback or custom-scheme redirect for installed apps (no secret).
    var redirectURI: String
    var scopes: [String]
    var authorizationEndpoint: URL
    var tokenEndpoint: URL

    init(
        clientId: String,
        redirectURI: String,
        scopes: [String] = ["https://www.googleapis.com/auth/calendar.events"],
        authorizationEndpoint: URL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!
    ) {
        self.clientId = clientId
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
    }
}

enum GoogleOAuthURLBuilder {
    /// Build the authorization URL the user is sent to (PKCE, offline access so
    /// Google returns a refresh token).
    static func authorizationURL(config: GoogleOAuthConfig, pkce: PKCEPair, state: String) -> URL? {
        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components?.url
    }

    /// Extract the authorization `code` from a redirect callback URL, validating
    /// the `state` matches what we sent (CSRF protection).
    static func authorizationCode(fromCallback url: URL, expectedState: String) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }
        let state = items.first { $0.name == "state" }?.value
        guard state == expectedState else { return nil }
        return items.first { $0.name == "code" }?.value
    }

    /// Body for the authorization-code → token exchange (PKCE, no secret).
    static func tokenExchangeBody(config: GoogleOAuthConfig, code: String, verifier: String) -> Data? {
        formURLEncoded([
            "client_id": config.clientId,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": config.redirectURI,
        ])
    }

    /// Body for the refresh-token grant.
    static func tokenRefreshBody(config: GoogleOAuthConfig, refreshToken: String) -> Data? {
        formURLEncoded([
            "client_id": config.clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
    }

    static func formURLEncoded(_ params: [String: String]) -> Data? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = params.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return pairs.sorted().joined(separator: "&").data(using: .utf8)
    }
}

// MARK: - Google API DTOs + mapping (pure)

/// Subset of Google's token endpoint response.
struct GoogleTokenResponse: Codable {
    var access_token: String
    var expires_in: TimeInterval
    var refresh_token: String?
    var scope: String?

    func token(now: Date, fallbackRefreshToken: String?) -> OAuthToken {
        OAuthToken(
            accessToken: access_token,
            refreshToken: refresh_token ?? fallbackRefreshToken,
            expiresIn: expires_in,
            now: now,
            scope: scope
        )
    }
}

/// Subset of Google Calendar's `events.list` response.
struct GoogleEventsResponse: Codable {
    struct Item: Codable {
        struct When: Codable {
            var dateTime: String?
            var date: String?
        }
        var id: String
        var summary: String?
        var description: String?
        var start: When
        var end: When
        var updated: String?
    }
    var items: [Item]
}

enum GoogleEventMapper {
    static let rfc3339: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let rfc3339NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return rfc3339.date(from: string) ?? rfc3339NoFraction.date(from: string)
    }

    static func map(_ item: GoogleEventsResponse.Item, calendarId: String?) -> ExternalCalendarEvent? {
        guard let start = parseDate(item.start.dateTime),
              let end = parseDate(item.end.dateTime) else { return nil }
        return ExternalCalendarEvent(
            externalId: item.id,
            provider: .google,
            title: item.summary ?? "",
            startAt: start,
            endAt: end,
            isBogiCreated: CalendarEventTag.isBogiCreated(notes: item.description),
            bogiBlockId: CalendarEventTag.blockId(fromNotes: item.description),
            lastModified: parseDate(item.updated),
            calendarId: calendarId
        )
    }
}

// MARK: - Service

/// Drives the Google Calendar integration. Network/UI side effects live here;
/// all branching logic delegates to the pure helpers above so it can be tested.
final class GoogleCalendarService: NSObject, CalendarSource {
    let provider: CalendarProvider = .google

    private let config: GoogleOAuthConfig
    private let tokenStore: TokenStore
    private let account: String
    private let session: URLSession
    private let calendarId: String
    private let now: () -> Date

    init(
        config: GoogleOAuthConfig,
        tokenStore: TokenStore = KeychainTokenStore(),
        account: String = "default",
        calendarId: String = "primary",
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.config = config
        self.tokenStore = tokenStore
        self.account = account
        self.calendarId = calendarId
        self.session = session
        self.now = now
        super.init()
    }

    func requestAccess() async throws -> Bool {
        // If we already hold a usable/refreshable token, no browser flow needed.
        let stored = try tokenStore.load(account: account)
        switch TokenLogic.decision(for: stored, now: now()) {
        case .usable, .refresh:
            _ = try await validAccessToken()
            return true
        case .reauthenticate:
            try await authenticate()
            return true
        }
    }

    /// Full PKCE browser flow via ASWebAuthenticationSession, then exchange the
    /// code for tokens and persist them to the Keychain.
    func authenticate() async throws {
        let pkce = PKCE.generate()
        let state = PKCE.base64URLEncode(Data(PKCE.secureRandomBytes(16)))
        guard let authURL = GoogleOAuthURLBuilder.authorizationURL(config: config, pkce: pkce, state: state) else {
            throw CalendarSourceError.invalidResponse
        }
        let callback = try await presentWebAuth(url: authURL)
        guard let code = GoogleOAuthURLBuilder.authorizationCode(fromCallback: callback, expectedState: state) else {
            throw CalendarSourceError.notAuthenticated
        }
        guard let body = GoogleOAuthURLBuilder.tokenExchangeBody(config: config, code: code, verifier: pkce.verifier) else {
            throw CalendarSourceError.invalidResponse
        }
        let token = try await postToken(body: body, fallbackRefreshToken: nil)
        try tokenStore.save(token, account: account)
    }

    // MARK: CalendarSource

    func fetchEvents(from: Date, to: Date) async throws -> [ExternalCalendarEvent] {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events")
        components?.queryItems = [
            URLQueryItem(name: "timeMin", value: GoogleEventMapper.rfc3339.string(from: from)),
            URLQueryItem(name: "timeMax", value: GoogleEventMapper.rfc3339.string(from: to)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
        ]
        guard let url = components?.url else { throw CalendarSourceError.invalidResponse }
        let data = try await authorizedData(for: url, method: "GET", body: nil)
        let decoded = try JSONDecoder().decode(GoogleEventsResponse.self, from: data)
        return decoded.items.compactMap { GoogleEventMapper.map($0, calendarId: calendarId) }
    }

    func createBogiEvent(_ draft: CalendarEventDraft) async throws -> ExternalCalendarEvent {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events")!
        let body = try eventBody(for: draft)
        let data = try await authorizedData(for: url, method: "POST", body: body)
        let item = try JSONDecoder().decode(GoogleEventsResponse.Item.self, from: data)
        guard let event = GoogleEventMapper.map(item, calendarId: calendarId) else {
            throw CalendarSourceError.invalidResponse
        }
        return event
    }

    func updateBogiEvent(externalId: String, with draft: CalendarEventDraft) async throws -> ExternalCalendarEvent {
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events/\(externalId)")!
        let body = try eventBody(for: draft)
        let data = try await authorizedData(for: url, method: "PATCH", body: body)
        let item = try JSONDecoder().decode(GoogleEventsResponse.Item.self, from: data)
        guard let event = GoogleEventMapper.map(item, calendarId: calendarId) else {
            throw CalendarSourceError.invalidResponse
        }
        return event
    }

    func removeBogiEvent(externalId: String) async throws {
        // Confirm Bogi ownership before deleting so we never remove a user event.
        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events/\(externalId)")!
        let data = try await authorizedData(for: url, method: "GET", body: nil)
        let item = try JSONDecoder().decode(GoogleEventsResponse.Item.self, from: data)
        guard CalendarEventTag.isBogiCreated(notes: item.description) else {
            throw CalendarSourceError.notBogiOwned
        }
        _ = try await authorizedData(for: url, method: "DELETE", body: nil)
    }

    // MARK: - Networking helpers

    private func eventBody(for draft: CalendarEventDraft) throws -> Data {
        let payload: [String: Any] = [
            "summary": draft.title,
            "description": CalendarEventTag.annotate(notes: draft.notes, blockId: draft.bogiBlockId),
            "start": ["dateTime": GoogleEventMapper.rfc3339.string(from: draft.startAt)],
            "end": ["dateTime": GoogleEventMapper.rfc3339.string(from: draft.endAt)],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Perform a request with a valid bearer token, refreshing once on 401.
    private func authorizedData(for url: URL, method: String, body: Data?) async throws -> Data {
        var token = try await validAccessToken()
        var (data, status) = try await send(url: url, method: method, body: body, accessToken: token)
        if TokenLogic.decision(forStatus: status, token: try tokenStore.load(account: account)) == .refresh {
            token = try await refreshAccessToken()
            (data, status) = try await send(url: url, method: method, body: body, accessToken: token)
        }
        guard (200..<300).contains(status) else { throw CalendarSourceError.http(status: status) }
        return data
    }

    private func send(url: URL, method: String, body: Data?, accessToken: String) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    /// Return a usable access token, refreshing or re-authing as the pure
    /// `TokenLogic` dictates.
    private func validAccessToken() async throws -> String {
        let stored = try tokenStore.load(account: account)
        switch TokenLogic.decision(for: stored, now: now()) {
        case .usable:
            return stored!.accessToken
        case .refresh:
            return try await refreshAccessToken()
        case .reauthenticate:
            try await authenticate()
            guard let token = try tokenStore.load(account: account) else {
                throw CalendarSourceError.notAuthenticated
            }
            return token.accessToken
        }
    }

    private func refreshAccessToken() async throws -> String {
        guard let stored = try tokenStore.load(account: account),
              let refreshToken = stored.refreshToken,
              let body = GoogleOAuthURLBuilder.tokenRefreshBody(config: config, refreshToken: refreshToken)
        else {
            throw CalendarSourceError.notAuthenticated
        }
        let token = try await postToken(body: body, fallbackRefreshToken: refreshToken)
        try tokenStore.save(token, account: account)
        return token.accessToken
    }

    private func postToken(body: Data, fallbackRefreshToken: String?) async throws -> OAuthToken {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw CalendarSourceError.http(status: status) }
        let decoded = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        return decoded.token(now: now(), fallbackRefreshToken: fallbackRefreshToken)
    }

    // MARK: - Web auth

    private func presentWebAuth(url: URL) async throws -> URL {
        #if canImport(AuthenticationServices)
        let scheme = URL(string: config.redirectURI)?.scheme
        return try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let error { cont.resume(throwing: error) }
                else if let callbackURL { cont.resume(returning: callbackURL) }
                else { cont.resume(throwing: CalendarSourceError.notAuthenticated) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                cont.resume(throwing: CalendarSourceError.notAuthenticated)
            }
        }
        #else
        throw CalendarSourceError.notAuthenticated
        #endif
    }
}

#if canImport(AuthenticationServices)
extension GoogleCalendarService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
#endif
