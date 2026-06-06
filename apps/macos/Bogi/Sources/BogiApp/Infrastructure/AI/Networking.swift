import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal seam over `URLSession` so request building and status-code → error
/// mapping can be unit-tested with a stubbed transport. `URLSession` conforms
/// directly, so production code passes `URLSession.shared`.
protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Where the backend proxy lives. The Bedrock API key never ships in the client;
/// every authorized call goes through these endpoints carrying the Supabase JWT.
///
/// The base URL is resolved (in priority order) from:
///  1. an explicit value (e.g. a Settings-backed override),
///  2. the `BOGI_BACKEND_BASE_URL` environment variable (useful for tests / dev),
///  3. the `BogiBackendBaseURL` key in the app's `Info.plist`,
///  4. the compiled-in `production` default.
struct BackendConfig: Equatable {
    var baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Compiled-in production endpoint. Adjust here (or override via Info.plist /
    /// environment) when the deployed API Gateway hostname is finalized.
    static let production = BackendConfig(baseURL: URL(string: "https://api.bogi.app")!)

    /// Resolve the backend base URL from the runtime environment, falling back to
    /// `production`. Accepts an injectable `bundle`/`environment` for testing.
    static func resolved(
        override: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> BackendConfig {
        let candidates: [String?] = [
            override,
            environment["BOGI_BACKEND_BASE_URL"],
            bundle.object(forInfoDictionaryKey: "BogiBackendBaseURL") as? String,
        ]
        for case let raw? in candidates {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) {
                return BackendConfig(baseURL: url)
            }
        }
        return production
    }

    /// `POST /v1/infer` — backend inference proxy.
    var inferURL: URL { baseURL.appendingPathComponent("v1/infer") }

    /// `GET /v1/account/status` — paid-status check.
    var accountStatusURL: URL { baseURL.appendingPathComponent("v1/account/status") }
}
