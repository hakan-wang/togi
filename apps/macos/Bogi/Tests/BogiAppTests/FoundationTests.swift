import XCTest
@testable import BogiApp

final class FoundationTests: XCTestCase {
    func testSettingsStoreDefaultsAndRoundTrip() throws {
        let service = try DatabaseService(inMemory: true)
        let settings = SettingsStore(database: service)

        XCTAssertEqual(settings.rawRetentionDays, 14)
        XCTAssertFalse(settings.isPaused)

        settings.set(.rawRetentionDays, "30")
        settings.setBool(.paused, true)

        XCTAssertEqual(settings.rawRetentionDays, 30)
        XCTAssertTrue(settings.isPaused)
    }

    func testPermissionSnapshotCaptureReady() {
        var snapshot = PermissionSnapshot.unknown
        XCTAssertFalse(snapshot.captureReady)
        snapshot.accessibility = .granted
        XCTAssertTrue(snapshot.captureReady)
    }

    func testInferenceRequestEncodesSnakeCase() throws {
        let request = InferenceRequest(
            messages: [InferenceMessage(role: .user, content: "hi")],
            maxTokens: 256
        )
        let data = try JSONEncoder().encode(request)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"max_tokens\":256"))
    }
}
