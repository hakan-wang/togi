import Foundation
import Speech
import AVFoundation

/// Push-to-talk dictation for "talk to Togi". Wraps `SFSpeechRecognizer` + `AVAudioEngine`
/// and finalises the transcript automatically after a short silence (or a hard cap, or an
/// explicit `stop()`), then hands it back via the `onFinal` callback. Defensive throughout:
/// if speech/mic permission is missing or no recognizer is available it simply returns an
/// empty transcript rather than crashing.
@MainActor
final class SpeechRecognizer: ObservableObject {
    /// The live, partial transcript while listening. Drives the on-screen caption.
    @Published private(set) var transcript: String = ""
    /// True between `start()` and the moment listening ends.
    @Published private(set) var isListening: Bool = false

    enum AuthState { case unknown, authorized, denied }
    @Published private(set) var auth: AuthState = .unknown

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var maxTimer: Timer?
    private var tapInstalled = false
    private var didFinish = false
    private var onFinal: ((String) -> Void)?

    /// How long a pause ends the turn, and the longest a single turn may run.
    private let silenceSeconds: TimeInterval = 1.8
    private let maxSeconds: TimeInterval = 15

    // MARK: - Authorization

    /// Request speech-recognition + microphone permission. Returns true only if BOTH are granted.
    func requestAuthorization() async -> Bool {
        let speechOK: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micOK = await AVCaptureDevice.requestAccess(for: .audio)
        let granted = speechOK && micOK
        auth = granted ? .authorized : .denied
        return granted
    }

    // MARK: - Listen

    /// Begin listening. `onFinal` fires exactly once with the trimmed final transcript.
    func start(onFinal: @escaping (String) -> Void) {
        guard !isListening else { return }
        self.onFinal = onFinal
        self.didFinish = false
        self.transcript = ""

        guard let recognizer, recognizer.isAvailable else {
            finish(with: "")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        self.request = req

        // The tap runs on the realtime audio thread, so it must not touch main-actor state.
        // Capture the request locally and only append buffers to it.
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            finish(with: "")
            return
        }

        isListening = true
        armTimers()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.armTimers()
                    if result.isFinal { self.finish(with: self.transcript) }
                }
                if error != nil { self.finish(with: self.transcript) }
            }
        }
    }

    /// End the turn now and deliver whatever has been transcribed so far.
    func stop() { finish(with: transcript) }

    /// Tear down without delivering a transcript (used when the user cancels the whole session).
    func abort() {
        onFinal = nil
        finish(with: "")
    }

    // MARK: - Internals

    private func armTimers() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        if maxTimer == nil {
            maxTimer = Timer.scheduledTimer(withTimeInterval: maxSeconds, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }

    private func finish(with text: String) {
        guard !didFinish else { return }
        didFinish = true

        silenceTimer?.invalidate(); silenceTimer = nil
        maxTimer?.invalidate(); maxTimer = nil

        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false

        let callback = onFinal
        onFinal = nil
        callback?(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
