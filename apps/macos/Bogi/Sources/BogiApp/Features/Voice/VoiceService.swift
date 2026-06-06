import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

// Push-to-talk voice capture for "Hey Bogi". Audio is captured with
// `AVAudioEngine` while the hotkey is held, then transcribed via a `Transcribing`
// backend (the inference proxy or a transcription endpoint). The recording
// lifecycle is modeled as a pure state machine so it is fully unit-testable
// without audio hardware.

/// The lifecycle of a single push-to-talk capture.
enum VoiceRecordingState: Equatable {
    case idle
    case requestingPermission
    case recording
    case transcribing
    case finished(transcript: String)
    case failed(reason: String)
}

/// Events that drive `VoiceRecordingState` transitions.
enum VoiceEvent: Equatable {
    case pressDown            // push-to-talk key pressed
    case permissionGranted
    case permissionDenied
    case releaseKey           // key released → stop capturing, start transcribing
    case transcript(String)   // transcription completed
    case failure(String)
    case reset                // dismiss result/error → back to idle
}

/// Pure transition function for the recording state machine. Invalid
/// event/state combinations are no-ops (return the current state) so the UI can
/// fire events liberally.
enum VoiceStateMachine {
    static func transition(_ state: VoiceRecordingState, on event: VoiceEvent) -> VoiceRecordingState {
        switch (state, event) {
        case (.idle, .pressDown):
            return .requestingPermission
        case (.requestingPermission, .permissionGranted):
            return .recording
        case (.requestingPermission, .permissionDenied):
            return .failed(reason: "Microphone access denied")
        // Releasing before/while requesting permission cancels back to idle.
        case (.requestingPermission, .releaseKey):
            return .idle
        case (.recording, .releaseKey):
            return .transcribing
        case (.transcribing, .transcript(let text)):
            return .finished(transcript: text)
        // A failure can interrupt recording or transcription.
        case (.recording, .failure(let reason)),
             (.transcribing, .failure(let reason)),
             (.requestingPermission, .failure(let reason)):
            return .failed(reason: reason)
        case (_, .reset):
            return .idle
        default:
            return state
        }
    }
}

/// Abstracts speech-to-text so `VoiceService` is testable and the transport
/// (inference proxy vs dedicated transcription endpoint) can be swapped.
protocol Transcribing {
    func transcribe(_ audio: Data) async throws -> String
}

enum VoiceError: Error, Equatable {
    case permissionDenied
    case captureUnavailable
    case noAudioCaptured
}

#if canImport(AVFoundation)
/// Drives audio capture and transcription, exposing observable state for the UI.
/// All branching goes through `VoiceStateMachine`; this type only performs the
/// AVAudioEngine side effects.
@MainActor
final class VoiceService: ObservableObject {
    @Published private(set) var state: VoiceRecordingState = .idle

    private let engine: AVAudioEngine
    private let transcriber: Transcribing
    private var capturedBuffers: [AVAudioPCMBuffer] = []

    init(transcriber: Transcribing, engine: AVAudioEngine = AVAudioEngine()) {
        self.transcriber = transcriber
        self.engine = engine
    }

    private func send(_ event: VoiceEvent) {
        state = VoiceStateMachine.transition(state, on: event)
    }

    /// Begin push-to-talk: request mic permission, then start the engine tap.
    func beginRecording() async {
        send(.pressDown)
        let granted = await requestMicrophoneAccess()
        guard state == .requestingPermission else { return } // released early
        send(granted ? .permissionGranted : .permissionDenied)
        guard granted else { return }
        do {
            try startEngine()
        } catch {
            send(.failure("Could not start audio engine"))
        }
    }

    /// Release push-to-talk: stop capture and transcribe what we gathered.
    func endRecording() async {
        guard state == .recording else {
            send(.releaseKey) // handle early release from requestingPermission
            return
        }
        stopEngine()
        send(.releaseKey)
        do {
            let data = try encodeCapturedAudio()
            let text = try await transcriber.transcribe(data)
            send(.transcript(text))
        } catch {
            send(.failure("Transcription failed"))
        }
    }

    func reset() { send(.reset) }

    // MARK: - AVAudioEngine

    private func startEngine() throws {
        capturedBuffers.removeAll()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            // Copy the buffer; the tap reuses its storage.
            if let copy = buffer.copyPCM() {
                Task { @MainActor in self?.capturedBuffers.append(copy) }
            }
        }
        engine.prepare()
        try engine.start()
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Flatten captured PCM into a single 16-bit little-endian blob the
    /// transcription backend accepts. Throws if nothing was captured.
    private func encodeCapturedAudio() throws -> Data {
        guard !capturedBuffers.isEmpty else { throw VoiceError.noAudioCaptured }
        var data = Data()
        for buffer in capturedBuffers {
            data.append(buffer.int16LEData())
        }
        guard !data.isEmpty else { throw VoiceError.noAudioCaptured }
        return data
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in cont.resume(returning: granted) }
            default:
                cont.resume(returning: false)
            }
        }
    }
}

extension AVAudioPCMBuffer {
    /// Deep-copy a PCM buffer so it survives past the tap callback.
    func copyPCM() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        copy.frameLength = frameLength
        let channels = Int(format.channelCount)
        if let src = floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channels {
                dst[ch].update(from: src[ch], count: Int(frameLength))
            }
        }
        return copy
    }

    /// Convert float PCM samples to interleaved 16-bit little-endian PCM bytes.
    func int16LEData() -> Data {
        guard let channelData = floatChannelData else { return Data() }
        let channels = Int(format.channelCount)
        let frames = Int(frameLength)
        var data = Data(capacity: frames * channels * 2)
        for frame in 0..<frames {
            for ch in 0..<channels {
                let sample = max(-1.0, min(1.0, channelData[ch][frame]))
                let scaled = Int16(sample * Float(Int16.max))
                withUnsafeBytes(of: scaled.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }
}
#endif

/// Transcribes audio by posting it to the backend (e.g. a `/v1/transcribe`
/// endpoint). Kept separate from `InferenceClient` because that contract is
/// text-only; the integrator wires the concrete transport.
struct ProxyTranscriber: Transcribing {
    let endpoint: URL
    let authToken: () -> String?
    let session: URLSession

    init(endpoint: URL, authToken: @escaping () -> String?, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.authToken = authToken
        self.session = session
    }

    func transcribe(_ audio: Data) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let token = authToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = audio
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw InferenceError.http(status: status) }
        struct TranscriptResponse: Codable { var text: String }
        return try JSONDecoder().decode(TranscriptResponse.self, from: data).text
    }
}
