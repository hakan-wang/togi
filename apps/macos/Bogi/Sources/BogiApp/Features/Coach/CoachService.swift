import Foundation

/// Forwards a question to the on-device agent, which queries the data bank via tools.
protocol CoachBackend {
    func chat(_ text: String, threadId: String) async throws -> String
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
}
