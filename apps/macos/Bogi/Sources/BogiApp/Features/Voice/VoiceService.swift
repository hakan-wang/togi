import AVFoundation

@MainActor
final class VoiceService: ObservableObject {
    @Published private(set) var state: VoiceRecordingState = .idle
    private let engine = AVAudioEngine()

    func startPushToTalk() {
        state = .recording
    }

    func stopPushToTalk() {
        if engine.isRunning {
            engine.stop()
        }
        state = .transcribing
    }

    func markTranscriptionComplete() {
        state = .idle
    }
}
