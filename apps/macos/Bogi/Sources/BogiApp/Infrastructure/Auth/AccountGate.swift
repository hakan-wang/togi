import Foundation

/// Checks paid status against the backend. Bogi is paid-account-first: only paid accounts
/// may use the app; unpaid users are sent to the website to pay.
final class AccountGate {
    struct Status: Decodable { let paid: Bool; let plan: String? }

    private let baseURL: URL
    private let auth: SupabaseAuth

    init(baseURL: URL = BackendConfig.baseURL, auth: SupabaseAuth) {
        self.baseURL = baseURL
        self.auth = auth
    }

    /// Returns paid status, or false if not signed in / unreachable.
    func isPaid() async -> Bool {
        guard let token = await auth.currentAccessToken() else { return false }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/account/status"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "X-Bogi-Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let status = try? JSONDecoder().decode(Status.self, from: data) else { return false }
        return status.paid
    }
}
