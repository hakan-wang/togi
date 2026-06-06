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
    /// Live mic input level, 0…1, while listening — drives the recording waveform.
    @Published private(set) var level: Float = 0

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
    private var autoStop = true
    private var onFinal: ((String) -> Void)?

    /// How long a pause ends the turn, and the longest a single turn may run.
    private let silenceSeconds: TimeInterval = 1.1
    private let maxSeconds: TimeInterval = 20

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
    func start(autoStop: Bool = true, onFinal: @escaping (String) -> Void) {
        guard !isListening else { return }
        self.onFinal = onFinal
        self.autoStop = autoStop
        self.didFinish = false
        self.transcript = ""
        self.level = 0

        guard let recognizer, recognizer.isAvailable else {
            finish(with: "")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // On-device recognition gives faster, lower-latency partial results so the caption
        // updates while you talk, not after you stop.
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        self.request = req

        // The tap runs on the realtime audio thread, so it must not touch main-actor state.
        // Capture the request locally and only append buffers to it.
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            let rms = SpeechRecognizer.rms(of: buffer)
            Task { @MainActor in self?.updateLevel(rms) }
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
        // Push-to-talk (hold Control) sets autoStop = false: the turn ends only on release or
        // the hard cap, never on a pause, so you can think mid-sentence while holding.
        if autoStop {
            silenceTimer?.invalidate()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceSeconds, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    // Don't end the turn on the opening silence — Togi may have just asked a
                    // question and the user is still gathering their thought. Only a pause *after*
                    // they've started talking ends the turn; until the first word, keep the mic
                    // open (the hard cap still applies).
                    if self.transcript.isEmpty {
                        self.armTimers()
                    } else {
                        self.stop()
                    }
                }
            }
        }
        if maxTimer == nil {
            maxTimer = Timer.scheduledTimer(withTimeInterval: maxSeconds, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }

    /// Root-mean-square amplitude of a buffer (0…~1), computed on the audio thread.
    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { let sample = channel[i]; sum += sample * sample }
        return (sum / Float(count)).squareRoot()
    }

    /// Smooth the raw RMS into a lively 0…1 level for the waveform.
    private func updateLevel(_ rms: Float) {
        let scaled = min(1, max(0, rms * 12))
        level = level * 0.6 + scaled * 0.4
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
        level = 0

        let callback = onFinal
        onFinal = nil
        callback?(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
