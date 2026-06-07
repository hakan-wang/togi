import XCTest
@testable import BogiApp

final class FakeTransport: SidecarTransport {
    var onLine: ((String) -> Void)?
    var onTerminate: (() -> Void)?
    private(set) var sent: [String] = []
    private(set) var startCount = 0
    private(set) var isRunning = false
    /// Returns a single reply line for a sent request.
    var autoReply: ((String) -> String?)?
    /// Returns zero or more reply lines for a sent request (e.g. token frames + result).
    var autoReplies: ((String) -> [String])?
    func start() throws { startCount += 1; isRunning = true }
    func stop() { isRunning = false }
    func send(_ line: String) {
        sent.append(line)
        if let reply = autoReply?(line) { onLine?(reply) }
        if let replies = autoReplies?(line) { replies.forEach { onLine?($0) } }
    }
    func simulateCrash() { isRunning = false; onTerminate?() }

    /// Extracts the request id from a JSON request line.
    static func idFrom(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["id"] as? String
    }
}

final class SidecarClientTests: XCTestCase {
    func testChatResolvesWithResultText() async throws {
        let transport = FakeTransport()
        transport.autoReply = { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String else { return nil }
            return #"{"kind":"result","id":"\#(id)","ok":true,"text":"you focused 2h"}"#
        }
        let client = SidecarClient(transport: transport)
        try client.start()
        let answer = try await client.chat("how was today?", threadId: "t1")
        XCTAssertEqual(answer, "you focused 2h")
        XCTAssertTrue(transport.sent.first?.contains("\"kind\":\"chat\"") == true)
    }

    func testCrashFailsPendingAndRestarts() async throws {
        let transport = FakeTransport()
        transport.autoReply = { _ in nil }  // never replies; we will crash instead
        let client = SidecarClient(transport: transport, restartDelay: 0)
        try client.start()
        XCTAssertEqual(transport.startCount, 1)

        let task = Task { try await client.chat("hi", threadId: "t1") }
        // Give the request a moment to register, then crash.
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.simulateCrash()

        do { _ = try await task.value; XCTFail("expected failure") }
        catch { /* pending request failed as expected */ }

        // Backoff is 0, so a restart should have happened.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertGreaterThanOrEqual(transport.startCount, 2)
    }

    func testTokenFramesStreamToHandler() async throws {
        let transport = FakeTransport()
        var streamed = ""
        transport.autoReplies = { line in
            guard let id = FakeTransport.idFrom(line) else { return [] }
            // Two token frames for this id, then the final result frame.
            return [
                #"{"kind":"token","id":"\#(id)","text":"Hel"}"#,
                #"{"kind":"token","id":"\#(id)","text":"lo"}"#,
                #"{"kind":"result","id":"\#(id)","ok":true,"text":"Hello"}"#,
            ]
        }
        let client = SidecarClient(transport: transport)
        try client.start()
        let result = try await client.chat("hi", threadId: "t", onToken: { streamed += $0 })
        XCTAssertEqual(streamed, "Hello")
        XCTAssertEqual(result, "Hello")
    }

    func testRequestIncludesFreshTokenFromProvider() async throws {
        let transport = FakeTransport()
        transport.autoReply = { line in
            guard let id = FakeTransport.idFrom(line) else { return nil }
            return #"{"kind":"result","id":"\#(id)","ok":true,"text":"ok"}"#
        }
        let client = SidecarClient(transport: transport)
        client.tokenProvider = { "fresh-token-123" }
        try client.start()
        _ = try await client.chat("hi", threadId: "t1")
        XCTAssertTrue(transport.sent.first?.contains("\"token\":\"fresh-token-123\"") == true)
    }

    func testRequestOmitsTokenWhenNoProvider() async throws {
        let transport = FakeTransport()
        transport.autoReply = { line in
            guard let id = FakeTransport.idFrom(line) else { return nil }
            return #"{"kind":"result","id":"\#(id)","ok":true,"text":"ok"}"#
        }
        let client = SidecarClient(transport: transport)
        try client.start()
        _ = try await client.chat("hi", threadId: "t1")
        XCTAssertFalse(transport.sent.first?.contains("\"token\"") == true)
    }

    func testRequestTimesOutWhenSidecarStaysSilent() async throws {
        let transport = FakeTransport()
        transport.autoReply = { _ in nil }  // process is "running" but never answers
        let client = SidecarClient(transport: transport, requestTimeout: 0.1)
        try client.start()
        do {
            _ = try await client.chat("hi", threadId: "t1")
            XCTFail("expected a timeout")
        } catch let error as SidecarError {
            guard case .timedOut = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    func testRequestFailsFastWhenSidecarNotRunning() async throws {
        let transport = FakeTransport()  // never started → not running
        let client = SidecarClient(transport: transport, requestTimeout: 5)
        do {
            _ = try await client.chat("hi", threadId: "t1")
            XCTFail("expected a not-running failure")
        } catch let error as SidecarError {
            guard case .notRunning = error else { return XCTFail("wrong error: \(error)") }
        }
        XCTAssertTrue(transport.sent.isEmpty, "must not write into a dead pipe")
    }

    func testStreamedTokensKeepRequestAlivePastTimeout() async throws {
        // A request that streams a token every 50ms must NOT trip a 0.15s inactivity timeout,
        // because each token resets the watchdog. Final result arrives after ~200ms total.
        let transport = FakeTransport()
        let client = SidecarClient(transport: transport, requestTimeout: 0.15)
        try client.start()
        // Drive token/result frames out-of-band on a timer keyed to the sent request id. Capture
        // the client's line handler so the async emits don't reference the transport directly.
        transport.autoReply = { line in
            guard let id = FakeTransport.idFrom(line), let emit = transport.onLine else { return nil }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { emit(#"{"kind":"token","id":"\#(id)","text":"a"}"#) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.10) { emit(#"{"kind":"token","id":"\#(id)","text":"b"}"#) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.20) { emit(#"{"kind":"result","id":"\#(id)","ok":true,"text":"ab"}"#) }
            return nil
        }
        var streamed = ""
        let result = try await client.chat("hi", threadId: "t", onToken: { streamed += $0 })
        XCTAssertEqual(result, "ab")
        XCTAssertEqual(streamed, "ab")
    }

    func testBackoffGrowsBetweenCrashes() async throws {
        let transport = FakeTransport()
        let client = SidecarClient(transport: transport, restartDelay: 0.01)
        try client.start()
        transport.simulateCrash()
        try await Task.sleep(nanoseconds: 60_000_000)
        let afterFirst = transport.startCount
        transport.simulateCrash()
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertGreaterThan(transport.startCount, afterFirst)
    }
}
