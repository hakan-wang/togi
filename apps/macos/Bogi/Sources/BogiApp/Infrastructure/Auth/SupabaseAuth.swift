import Foundation

/// Supabase email/password auth. Stores the refresh token in the Keychain and vends a
/// fresh access token (refreshing on expiry). The access token is sent to the backend as
/// `X-Bogi-Authorization` for paid-gated calls.
final class SupabaseAuth {
    struct Session: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    enum AuthError: Error { case http(Int), decode, noSession }

    private let baseURL: URL
    private let anonKey: String
    private let keychain: KeychainStore
    private let account = "supabase-session"
    private var session: Session?

    init(baseURL: URL = SupabaseConfig.url,
         anonKey: String = SupabaseConfig.anonKey,
         keychain: KeychainStore = KeychainStore()) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.keychain = keychain
        if let data = keychain.read(account: account) {
            self.session = try? JSONDecoder().decode(Session.self, from: data)
        }
    }

    var isSignedIn: Bool { session != nil }

    /// Best-effort identity decoded from the current access token's JWT claims. Email/password
    /// sign-ups usually carry an email but no display name. Returns nils when signed out.
    func cachedIdentity() -> (email: String?, name: String?) {
        guard let token = session?.accessToken else { return (nil, nil) }
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return (nil, nil) }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        let email = json["email"] as? String
        var name: String?
        if let meta = json["user_metadata"] as? [String: Any] {
            name = (meta["full_name"] as? String) ?? (meta["name"] as? String)
        }
        return (email, name)
    }

    func signIn(email: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let token = try await tokenRequest(grant: "password", body: body)
        persist(token)
    }

    func signOut() {
        session = nil
        keychain.delete(account: account)
    }

    /// A valid access token, refreshing if within 60s of expiry. nil if not signed in.
    func currentAccessToken() async -> String? {
        guard let s = session else { return nil }
        if s.expiresAt.timeIntervalSinceNow > 60 { return s.accessToken }
        let body = try? JSONSerialization.data(withJSONObject: ["refresh_token": s.refreshToken])
        guard let body, let refreshed = try? await tokenRequest(grant: "refresh_token", body: body) else {
            return s.accessToken // best effort; backend will 401 if truly expired
        }
        persist(refreshed)
        return refreshed.access_token
    }

    // MARK: - internals

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double
    }

    private func tokenRequest(grant: String, body: Data) async throws -> TokenResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: grant)]))
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw AuthError.decode
        }
        return token
    }

    private func persist(_ t: TokenResponse) {
        let s = Session(accessToken: t.access_token, refreshToken: t.refresh_token,
                        expiresAt: Date().addingTimeInterval(t.expires_in))
        session = s
        if let data = try? JSONEncoder().encode(s) { keychain.save(data, account: account) }
    }
}
