import Foundation

/// Forwards a question to the on-device agent, which queries the data bank via tools.
protocol CoachBackend {
    func chat(_ text: String, threadId: String) async throws -> String
    /// Streaming variant: `onToken` is called for each token as it arrives; returns the
    /// final accumulated reply. Defaults to the non-streaming `chat` for backends that
    /// don't stream (the tokens simply never fire).
    func chat(_ text: String, threadId: String, onToken: ((String) -> Void)?) async throws -> String
}

extension CoachBackend {
    func chat(_ text: String, threadId: String, onToken: ((String) -> Void)?) async throws -> String {
        try await chat(text, threadId: threadId)
    }
}

extension SidecarClient: CoachBackend {}

/// The accountability coach. Persona, grounding, and data access now live in the agent
/// (sidecar); this type just carries the question to it on a stable conversation thread.
final class CoachService {
    private let backend: CoachBackend
    private let threadId: String

    init(backend: CoachBackend, threadId: String = "coach") {
        self.backend = backend
        self.threadId = threadId
    }

    func ask(_ question: String) async throws -> String {
        try await backend.chat(question, threadId: threadId)
    }

    /// Streaming ask: `onToken` fires for each token as the agent streams it; returns the
    /// final accumulated reply.
    func ask(_ question: String, onToken: @escaping (String) -> Void) async throws -> String {
        try await backend.chat(question, threadId: threadId, onToken: onToken)
    }
}
