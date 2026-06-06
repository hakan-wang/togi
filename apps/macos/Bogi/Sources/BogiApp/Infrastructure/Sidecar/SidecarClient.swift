import Foundation

/// Correlates request ids to continuations and decodes sidecar result/error lines.
/// Action calls (Phases D/E) are handled via `actionHandler`, set by the app.
final class SidecarClient {
    private let transport: SidecarTransport
    private var pending: [String: CheckedContinuation<String, Error>] = [:]
    /// Per-request streaming-token callbacks, keyed by request id. Cleared on resolve.
    private var tokenHandlers: [String: (String) -> Void] = [:]
    private var counter = 0
    private let lock = NSLock()
    private let restartDelay: TimeInterval
    private var restartAttempts = 0
    /// Returns a JSON-encodable result for an action call (name, input) -> result.
    var actionHandler: ((_ name: String, _ input: [String: Any]) async -> [String: Any])?
    /// Supplies a fresh auth token for each outgoing chat/plan/judge request. The token
    /// rotates ~hourly, so it is fetched per-request rather than baked in at launch. When
    /// nil (or it returns nil), the `token` field is omitted and the sidecar falls back to
    /// its launch-time env token.
    var tokenProvider: (() async -> String?)?

    init(transport: SidecarTransport, restartDelay: TimeInterval = 1.0) {
        self.transport = transport
        self.restartDelay = restartDelay
        self.transport.onLine = { [weak self] line in self?.handle(line) }
        self.transport.onTerminate = { [weak self] in self?.handleTermination() }
    }

    func start() throws { try transport.start() }
    func stop() { transport.stop() }

    private func nextId() -> String {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        return "req-\(counter)"
    }

    func chat(_ text: String, threadId: String) async throws -> String {
        try await chat(text, threadId: threadId, onToken: nil)
    }

    /// Streaming chat: `onToken` is invoked for each `token` frame as it arrives, and the
    /// returned value is the final accumulated reply text.
    func chat(_ text: String, threadId: String, onToken: ((String) -> Void)?) async throws -> String {
        try await request(kind: "chat", threadId: threadId, text: text, onToken: onToken)
    }

    func plan(_ text: String, threadId: String) async throws -> String {
        try await request(kind: "plan", threadId: threadId, text: text)
    }

    func judge(_ text: String, threadId: String) async throws -> String {
        try await request(kind: "judge", threadId: threadId, text: text)
    }

    private func request(kind: String, threadId: String, text: String,
                         onToken: ((String) -> Void)? = nil) async throws -> String {
        let id = nextId()
        // Fetch a fresh auth token per request (it rotates ~hourly). Omitted when no
        // provider is set so the sidecar falls back to its launch-time env token.
        let token = await tokenProvider?()
        var payload: [String: Any] = ["kind": kind, "id": id, "threadId": threadId, "text": text]
        if let token { payload["token"] = token }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let line = String(data: data, encoding: .utf8)! + "\n"
        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            pending[id] = cont
            if let onToken { tokenHandlers[id] = onToken }
            lock.unlock()
            transport.send(line)
        }
    }

    private func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = obj["kind"] as? String else { return }
        // A healthy sidecar that produces valid lines clears the restart backoff.
        lock.lock(); restartAttempts = 0; lock.unlock()
        switch kind {
        case "token":
            guard let id = obj["id"] as? String, let text = obj["text"] as? String else { return }
            lock.lock(); let handler = tokenHandlers[id]; lock.unlock()
            handler?(text)
        case "result":
            guard let id = obj["id"] as? String else { return }
            resolve(id, .success((obj["text"] as? String) ?? ""))
        case "error":
            guard let id = obj["id"] as? String else { return }
            resolve(id, .failure(SidecarError.remote((obj["message"] as? String) ?? "sidecar error")))
        case "action_call":
            handleAction(obj)
        default:
            break
        }
    }

    private func handleAction(_ obj: [String: Any]) {
        guard let id = obj["id"] as? String, let callId = obj["callId"] as? String,
              let name = obj["name"] as? String else { return }
        let input = (obj["input"] as? [String: Any]) ?? [:]
        Task {
            let result = await actionHandler?(name, input) ?? ["ok": false, "error": "no handler"]
            let payload: [String: Any] = ["kind": "action_result", "id": id, "callId": callId,
                                          "ok": true, "result": result]
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let s = String(data: data, encoding: .utf8) { transport.send(s + "\n") }
        }
    }

    private func handleTermination() {
        // Fail all in-flight requests so callers do not hang.
        lock.lock()
        let waiting = pending
        pending.removeAll()
        restartAttempts += 1
        let attempt = restartAttempts
        lock.unlock()
        for (_, cont) in waiting { cont.resume(throwing: SidecarError.terminated) }

        // Restart after an exponential, capped backoff. A successful decode resets the counter.
        let delay = min(restartDelay * pow(2, Double(attempt - 1)), 30)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            try? self?.transport.start()
        }
    }

    private func resolve(_ id: String, _ result: Result<String, Error>) {
        lock.lock()
        let cont = pending.removeValue(forKey: id)
        tokenHandlers.removeValue(forKey: id)
        lock.unlock()
        switch result {
        case .success(let s): cont?.resume(returning: s)
        case .failure(let e): cont?.resume(throwing: e)
        }
    }
}

enum SidecarError: Error { case remote(String); case terminated }
