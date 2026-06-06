import Foundation

/// The four states the subscription gate can resolve to. `unreachable` is distinct from
/// `notSubscribed` so the app can show a Retry screen (strict online check) rather than
/// wrongly telling a paying user to subscribe when the network is down.
enum GateOutcome: Equatable {
    case subscribed
    case notSubscribed
    case signedOut
    case unreachable
}

/// Checks subscription status against the backend. Togi is subscription-first: only signed-in
/// users with an active subscription may use the app.
final class AccountGate {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    struct Status: Decodable { let paid: Bool; let plan: String? }

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
            let (data, resp) = try await transport(req)
            guard let http = resp as? HTTPURLResponse else { return .unreachable }
            switch http.statusCode {
            case 200:
                guard let status = try? JSONDecoder().decode(Status.self, from: data) else { return .unreachable }
                return status.paid ? .subscribed : .notSubscribed
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
