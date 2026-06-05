enum VoiceRecordingState: Equatable {
    case idle
    case recording
    case transcribing
    case failed(String)

    var isRecording: Bool {
        self == .recording
    }
}
