import XCTest
@testable import BogiApp

final class FakeTransport: SidecarTransport {
    var onLine: ((String) -> Void)?
    var onTerminate: (() -> Void)?
    private(set) var sent: [String] = []
    private(set) var startCount = 0
    /// Returns a single reply line for a sent request.
    var autoReply: ((String) -> String?)?
    /// Returns zero or more reply lines for a sent request (e.g. token frames + result).
    var autoReplies: ((String) -> [String])?
    func start() throws { startCount += 1 }
    func stop() {}
    func send(_ line: String) {
        sent.append(line)
        if let reply = autoReply?(line) { onLine?(reply) }
        if let replies = autoReplies?(line) { replies.forEach { onLine?($0) } }
    }
    func simulateCrash() { onTerminate?() }

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
