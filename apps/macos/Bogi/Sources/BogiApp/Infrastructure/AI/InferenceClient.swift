import Foundation

/// Contract for talking to the backend inference proxy (`POST /v1/infer`), which
/// forwards to AWS Bedrock (Claude Sonnet 4.6). The API key never ships in the
/// client; every call carries the Supabase JWT and the backend enforces paid
/// status. The judge, coach and planner all depend on this protocol so they can
/// be built and tested against a mock independently.
public protocol InferenceClient {
    func infer(_ request: InferenceRequest) async throws -> InferenceResponse
}

public struct InferenceMessage: Codable, Equatable {
    public enum Role: String, Codable { case system, user, assistant }
    public var role: Role
    public var content: String
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct InferenceRequest: Codable, Equatable {
    public var model: String?
    public var messages: [InferenceMessage]
    public var maxTokens: Int

    public init(messages: [InferenceMessage], maxTokens: Int = 1024, model: String? = nil) {
        self.messages = messages
        self.maxTokens = maxTokens
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxTokens = "max_tokens"
    }
}

public struct InferenceResponse: Codable, Equatable {
    public var text: String
    public init(text: String) { self.text = text }
}

public enum InferenceError: Error, Equatable {
    case notAuthenticated
    case notPaid
    case http(status: Int)
    case decoding
}
