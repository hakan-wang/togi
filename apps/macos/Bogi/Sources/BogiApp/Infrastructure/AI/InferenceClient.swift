import Foundation

/// One message in an inference request.
struct InferenceMessage {
    let role: String
    let content: String
}

/// Abstraction over the LLM. Implementations talk to a backend proxy (prod) or return
/// canned text (tests). Kept small so the judge logic stays testable without a network.
protocol InferenceClient {
    func infer(system: String?, messages: [InferenceMessage], maxTokens: Int) async throws -> String
}

/// Errors surfaced by ``BackendInferenceClient``.
enum InferenceError: Error {
    case badStatus(Int)
    case emptyResponse
    /// 403 from the backend: the user has no active subscription. The UI should react by
    /// re-running the launch gate and showing the Subscribe screen, not a generic error.
    case subscriptionRequired
}

/// Talks to the Bogi backend proxy (`<baseURL>/v1/infer`). The proxy holds the model
/// provider key — the app never does. Auth token is fetched lazily via `tokenProvider`.
final class BackendInferenceClient: InferenceClient {
    private let baseURL: URL
    private let tokenProvider: () async -> String?
    private let session: URLSession

    init(baseURL: URL,
         tokenProvider: @escaping () async -> String?,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    private struct RequestBody: Encodable {
        let system: String?
        let messages: [Message]
        let maxTokens: Int

        struct Message: Encodable {
            let role: String
            let content: String
        }

        enum CodingKeys: String, CodingKey {
            case system
            case messages
            case maxTokens
        }
    }

    private struct ResponseBody: Decodable {
        let text: String
    }

    func infer(system: String?, messages: [InferenceMessage], maxTokens: Int) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/infer"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "X-Bogi-Authorization")
        }

        let body = RequestBody(
            system: system,
            messages: messages.map { RequestBody.Message(role: $0.role, content: $0.content) },
            maxTokens: maxTokens
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 403 { throw InferenceError.subscriptionRequired }
            throw InferenceError.badStatus(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return decoded.text
    }
}
