import XCTest
@testable import BogiApp

final class VoiceRecordingStateTests: XCTestCase {
    func testInitialVoiceStateIsIdle() {
        let state = VoiceRecordingState.idle
        XCTAssertFalse(state.isRecording)
    }
}
