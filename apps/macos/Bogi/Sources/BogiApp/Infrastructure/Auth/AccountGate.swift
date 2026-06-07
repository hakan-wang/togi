import Foundation

/// The states the login gate can resolve to. `unreachable` is distinct from `signedOut` so the
/// app can show a Retry screen (strict online check) rather than wrongly bouncing a signed-in
/// user back to login when the network is down.
enum GateOutcome: Equatable {
    case signedIn
    case signedOut
    case unreachable
}

/// Checks sign-in status against the backend. Togi requires a signed-in account, but no
/// subscription — any signed-in user gets in.
final class AccountGate {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let tokenProvider: () async -> String?
    private let transport: Transport

    init(baseURL: URL = BackendConfig.baseURL,
         auth: SupabaseAuth,
         transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.baseURL = baseURL
        self.tokenProvider = { await auth.currentAccessToken() }
        self.transport = transport
    }

    /// Test seam: inject the token provider + transport directly.
    init(baseURL: URL,
         tokenProvider: @escaping () async -> String?,
         transport: @escaping Transport) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.transport = transport
    }

    /// Strict online check. Never silently treats an error as "not subscribed".
    func check() async -> GateOutcome {
        guard let token = await tokenProvider() else { return .signedOut }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/account/status"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "X-Bogi-Authorization")
        do {
            let (_, resp) = try await transport(req)
            guard let http = resp as? HTTPURLResponse else { return .unreachable }
            switch http.statusCode {
            case 200:
                return .signedIn
            case 401:
                return .signedOut
            default:
                return .unreachable
            }
        } catch {
            return .unreachable
        }
    }
}
