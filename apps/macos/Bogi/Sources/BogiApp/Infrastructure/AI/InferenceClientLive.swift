import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Live `InferenceClient` that talks to the backend proxy (`POST /v1/infer`).
///
/// The Bedrock API key never ships in the client: each request carries the
/// Supabase JWT as a `Bearer` token and the backend enforces auth + paid status.
/// HTTP status codes are mapped onto `InferenceError` so callers (judge, coach,
/// planner) can react uniformly:
///   - 401            → `.notAuthenticated`
///   - 402 / 403      → `.notPaid`
///   - other non-2xx  → `.http(status:)`
///   - decode failure → `.decoding`
///
/// `transport` and `tokenProvider` are injected so request building and the
/// status-code → error mapping are unit-testable with a stubbed transport.
final class InferenceClientLive: InferenceClient {
    private let config: BackendConfig
    private let transport: HTTPTransport
    private let tokenProvider: AccessTokenProviding
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        config: BackendConfig,
        tokenProvider: AccessTokenProviding,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.config = config
        self.tokenProvider = tokenProvider
        self.transport = transport
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func infer(_ request: InferenceRequest) async throws -> InferenceResponse {
        guard let token = await tokenProvider.accessToken(), !token.isEmpty else {
            throw InferenceError.notAuthenticated
        }

        var urlRequest = URLRequest(url: config.inferURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(urlRequest)
        } catch {
            // Treat transport-level failures (offline, DNS, TLS) as a generic
            // HTTP failure with no status rather than crashing the caller.
            throw InferenceError.http(status: -1)
        }

        guard let http = response as? HTTPURLResponse else {
            throw InferenceError.decoding
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(InferenceResponse.self, from: data)
            } catch {
                throw InferenceError.decoding
            }
        case 401:
            throw InferenceError.notAuthenticated
        case 402, 403:
            throw InferenceError.notPaid
        default:
            throw InferenceError.http(status: http.statusCode)
        }
    }
}
