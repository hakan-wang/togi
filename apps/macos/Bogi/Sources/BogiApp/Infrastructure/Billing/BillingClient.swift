import AppKit
import Foundation

/// Starts and manages a Togi Pro subscription through the backend's Stripe endpoints.
/// The backend holds the Stripe secret; this client only ever receives a hosted Stripe URL
/// (Checkout or Customer Portal) and opens it in the user's browser. Payment completion
/// arrives asynchronously via the Stripe webhook, which flips `profiles.paid` server-side,
/// so after returning from the browser the app should re-check `AccountGate.isPaid()`.
final class BillingClient {
    enum Plan: String { case monthly, annual }

    enum BillingError: Error {
        case unauthorized       // not signed in
        case notConfigured      // backend missing Stripe keys / price ids
        case noSubscription     // portal requested before any subscription exists
        case server(Int)
        case badResponse
    }

    private let baseURL: URL
    private let tokenProvider: () async -> String?
    private let session: URLSession

    init(baseURL: URL = BackendConfig.baseURL,
         tokenProvider: @escaping () async -> String?,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    private struct URLBody: Decodable { let url: String }

    /// Opens Stripe Checkout for the chosen plan in the default browser. Returns the URL once
    /// the browser has been launched.
    @discardableResult
    func startCheckout(plan: Plan = .monthly) async throws -> URL {
        let url = try await postForURL(path: "v1/stripe/checkout", body: ["plan": plan.rawValue])
        await MainActor.run { NSWorkspace.shared.open(url) }
        return url
    }

    /// Opens the Stripe Customer Portal (manage / cancel / switch plan) in the browser.
    @discardableResult
    func openPortal() async throws -> URL {
        let url = try await postForURL(path: "v1/stripe/portal", body: [:])
        await MainActor.run { NSWorkspace.shared.open(url) }
        return url
    }

    private func postForURL(path: String, body: [String: String]) async throws -> URL {
        guard let token = await tokenProvider() else { throw BillingError.unauthorized }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // CloudFront OAC owns `Authorization`, so the app sends the Supabase token here.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "X-Bogi-Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        switch status {
        case 200:
            guard let decoded = try? JSONDecoder().decode(URLBody.self, from: data),
                  let url = URL(string: decoded.url) else { throw BillingError.badResponse }
            return url
        case 401: throw BillingError.unauthorized
        case 409: throw BillingError.noSubscription
        case 503: throw BillingError.notConfigured
        default: throw BillingError.server(status)
        }
    }
}
