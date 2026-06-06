import Foundation
import Network

/// Minimal local HTTP listener used to capture the OAuth redirect for Google's installed-app
/// loopback flow (the supported path for Desktop OAuth clients; custom URI schemes are no longer
/// accepted by Google). Binds 127.0.0.1 on an OS-assigned ephemeral port, waits for the browser
/// to hit `/oauth2redirect?code=…`, returns the full callback URL, and serves a tiny "you can
/// close this tab" page. One-shot: it serves a single request and then cancels itself.
final class LoopbackOAuthListener {
    enum ListenerError: LocalizedError {
        case failedToStart(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .failedToStart(let detail): return "Couldn't start the local sign-in listener: \(detail)"
            case .cancelled: return "The sign-in listener was cancelled before a redirect arrived."
            }
        }
    }

    /// Loopback host literal we bind to and put in the redirect URI. 127.0.0.1 is preferred over
    /// `localhost` (no DNS, firewall-friendly, local-only) per RFC 8252.
    static let host = "127.0.0.1"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "sh.bogi.oauth.loopback")
    private var continuation: CheckedContinuation<URL, Error>?
    private var didResume = false
    /// Result captured before `waitForCallback()` registered its continuation. Without this, a
    /// redirect that arrives faster than the awaiting task would be lost and the flow would hang.
    private var pendingResult: Result<URL, Error>?

    /// The port the OS assigned once the listener is ready.
    private(set) var port: UInt16 = 0

    /// Create and start a listener on an ephemeral port. Throws if the socket can't be opened.
    init() throws {
        let params = NWParameters.tcp
        // Bind to the loopback interface only.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .init(Self.host), port: .any)
        do {
            listener = try NWListener(using: params)
        } catch {
            throw ListenerError.failedToStart(error.localizedDescription)
        }
    }

    /// Start listening and resolve once the OS has assigned a port. After this returns, `port`
    /// holds the bound port for use in the redirect URI.
    func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumedReady = false
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let p = self.listener.port?.rawValue { self.port = p }
                    if !resumedReady { resumedReady = true; cont.resume() }
                case .failed(let error):
                    if !resumedReady { resumedReady = true; cont.resume(throwing: ListenerError.failedToStart(error.localizedDescription)) }
                    self.finish(with: .failure(ListenerError.failedToStart(error.localizedDescription)))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    /// Await the redirect. Returns the full callback URL (`http://127.0.0.1:<port><target>`).
    func waitForCallback() async throws -> URL {
        // Cancellation (e.g. an auth timeout racing this) must wake the continuation, otherwise a
        // structured parent awaiting both would deadlock. onCancel tears the listener down, which
        // resumes us via finish().
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                queue.async { [weak self] in
                    guard let self else { cont.resume(throwing: ListenerError.cancelled); return }
                    // If the redirect already arrived, resolve immediately; otherwise wait for it.
                    if let pending = self.pendingResult {
                        self.pendingResult = nil
                        cont.resume(with: pending)
                    } else {
                        self.continuation = cont
                    }
                }
            }
        } onCancel: {
            cancel()
        }
    }

    /// Cancel the listener (e.g. on error or after success). Safe to call multiple times.
    func cancel() {
        queue.async { [weak self] in
            self?.finish(with: .failure(ListenerError.cancelled))
        }
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { connection.cancel(); return }
            if let data, let raw = String(data: data, encoding: .utf8),
               let target = Self.requestTarget(fromHTTPRequest: raw),
               let url = URL(string: "http://\(Self.host):\(self.port)\(target)") {
                self.respond(on: connection)
                self.finish(with: .success(url))
            } else {
                // Not the request we want (e.g. favicon) or unreadable; close it and keep waiting.
                connection.cancel()
                if error != nil { /* transient; the browser will retry the real redirect */ }
            }
        }
    }

    private func respond(on connection: NWConnection) {
        let body = """
        <!doctype html><html><head><meta charset="utf-8"><title>Bogi</title></head>
        <body style="font-family:-apple-system,system-ui;text-align:center;padding:3rem">
        <h2>You're connected 🎉</h2><p>You can close this tab and return to Bogi.</p>
        </body></html>
        """
        let bytes = Array(body.utf8)
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n" + body
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(with result: Result<URL, Error>) {
        guard !didResume else { return }
        didResume = true
        listener.cancel()
        if let cont = continuation {
            continuation = nil
            cont.resume(with: result)
        } else {
            // No one is awaiting yet — stash it for the next waitForCallback().
            pendingResult = result
        }
    }

    // MARK: - Pure parsing (testable)

    /// Extract the request target (path + optional query) from a raw HTTP request's request line.
    /// Returns nil for anything that isn't a well-formed `GET <target> HTTP/x.y` line.
    static func requestTarget(fromHTTPRequest raw: String) -> String? {
        guard let firstLine = raw.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first
            ?? raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
        else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[2].hasPrefix("HTTP/") else { return nil }
        let target = String(parts[1])
        return target.hasPrefix("/") ? target : nil
    }
}
