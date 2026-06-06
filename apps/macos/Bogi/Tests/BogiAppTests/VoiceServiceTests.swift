import XCTest
@testable import BogiApp

final class VoiceServiceTests: XCTestCase {
    private func run(_ events: [VoiceEvent], from start: VoiceRecordingState = .idle) -> VoiceRecordingState {
        events.reduce(start) { VoiceStateMachine.transition($0, on: $1) }
    }

    func testHappyPath() {
        let final = run([.pressDown, .permissionGranted, .releaseKey, .transcript("hey bogi plan my day")])
        XCTAssertEqual(final, .finished(transcript: "hey bogi plan my day"))
    }

    func testPermissionDeniedFails() {
        XCTAssertEqual(run([.pressDown, .permissionDenied]), .failed(reason: "Microphone access denied"))
    }

    func testReleaseWhileRequestingPermissionCancels() {
        XCTAssertEqual(run([.pressDown, .releaseKey]), .idle)
    }

    func testFailureDuringRecording() {
        XCTAssertEqual(run([.pressDown, .permissionGranted, .failure("engine error")]),
                       .failed(reason: "engine error"))
    }

    func testFailureDuringTranscription() {
        XCTAssertEqual(run([.pressDown, .permissionGranted, .releaseKey, .failure("network")]),
                       .failed(reason: "network"))
    }

    func testResetReturnsToIdleFromAnyState() {
        XCTAssertEqual(run([.pressDown, .permissionGranted, .releaseKey, .transcript("x"), .reset]), .idle)
        XCTAssertEqual(run([.pressDown, .permissionDenied, .reset]), .idle)
    }

    func testInvalidTransitionsAreNoOps() {
        // A transcript while idle should be ignored.
        XCTAssertEqual(VoiceStateMachine.transition(.idle, on: .transcript("x")), .idle)
        // Pressing again while recording does nothing.
        XCTAssertEqual(VoiceStateMachine.transition(.recording, on: .pressDown), .recording)
        // Releasing while transcribing does nothing.
        XCTAssertEqual(VoiceStateMachine.transition(.transcribing, on: .releaseKey), .transcribing)
    }

    func testStatesAreSequential() {
        XCTAssertEqual(VoiceStateMachine.transition(.idle, on: .pressDown), .requestingPermission)
        XCTAssertEqual(VoiceStateMachine.transition(.requestingPermission, on: .permissionGranted), .recording)
        XCTAssertEqual(VoiceStateMachine.transition(.recording, on: .releaseKey), .transcribing)
    }
}
