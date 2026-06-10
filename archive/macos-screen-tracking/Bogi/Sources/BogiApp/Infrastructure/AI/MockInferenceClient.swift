import Foundation

/// Returns a canned string for tests/previews — no network. Set `response` to control output.
final class MockInferenceClient: InferenceClient {
    var response: String
    /// Captures the last request so tests can assert on the prompt that was built.
    private(set) var lastSystem: String?
    private(set) var lastMessages: [InferenceMessage] = []

    init(response: String = "") {
        self.response = response
    }

    func infer(system: String?, messages: [InferenceMessage], maxTokens: Int) async throws -> String {
        lastSystem = system
        lastMessages = messages
        return response
    }
}
