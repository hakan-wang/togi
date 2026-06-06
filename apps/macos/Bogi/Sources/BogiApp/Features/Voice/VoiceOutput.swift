import Foundation
import AVFoundation

/// Togi's spoken voice. Prefers a premium ElevenLabs voice when an API key is configured,
/// and falls back to the built-in macOS speech synthesizer otherwise — so voice replies work
/// with no key at all and simply sound better once a key is dropped in.
///
/// Key resolution (first hit wins): `ELEVENLABS_API_KEY` env var → `elevenlabs_api_key` in
/// the settings table. Voice id likewise via `ELEVENLABS_VOICE_ID` → `elevenlabs_voice_id`,
/// defaulting to a warm public voice.
@MainActor
final class VoiceOutput: NSObject {
    private let settings: SettingsStore
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isSpeaking = false

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        synth.delegate = self
    }

    // MARK: - Config

    private var elevenKey: String? {
        if let env = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !env.isEmpty { return env }
        if let stored = settings.string("elevenlabs_api_key"), !stored.isEmpty { return stored }
        return nil
    }

    private var elevenVoiceId: String {
        if let env = ProcessInfo.processInfo.environment["ELEVENLABS_VOICE_ID"], !env.isEmpty { return env }
        if let stored = settings.string("elevenlabs_voice_id"), !stored.isEmpty { return stored }
        return "21m00Tcm4TlvDq8ikWAM"   // ElevenLabs "Rachel" — warm, friendly default
    }

    /// True when a premium voice is wired up. Used only to tell the user which voice they'll hear.
    var usesPremiumVoice: Bool { elevenKey != nil }

    // MARK: - Speak

    /// Speak `text` and return when it has finished playing. Safe to call repeatedly.
    func speak(_ text: String) async {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        stop()   // never talk over a previous line

        if let key = elevenKey, let data = try? await fetchElevenLabs(text: line, key: key), !data.isEmpty {
            await play(data)
        } else {
            await speakWithApple(line)
        }
    }

    /// Stop any in-flight speech immediately.
    func stop() {
        if let player { player.stop() }
        player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        finishSpeaking()
    }

    // MARK: - ElevenLabs

    private func fetchElevenLabs(text: String, key: String) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(elevenVoiceId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": ["stability": 0.45, "similarity_boost": 0.8]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw VoiceOutputError.badStatus(http.statusCode)
        }
        return data
    }

    private func play(_ data: Data) async {
        do {
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            player = p
            isSpeaking = true
            p.play()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                self.continuation = c
            }
        } catch {
            // Couldn't decode/play the audio — fall back so the user still hears the line.
            await speakWithApple(String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Apple fallback

    private func speakWithApple(_ text: String) async {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: line)
        utterance.voice = Self.preferredAppleVoice()
        isSpeaking = true
        synth.speak(utterance)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            self.continuation = c
        }
    }

    /// Pick the nicest installed English voice (premium → enhanced → any en).
    private static func preferredAppleVoice() -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return english.first(where: { $0.quality == .premium })
            ?? english.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func finishSpeaking() {
        isSpeaking = false
        player = nil
        let c = continuation
        continuation = nil
        c?.resume()
    }
}

enum VoiceOutputError: Error { case badStatus(Int) }

// AVAudioPlayer / AVSpeechSynthesizer deliver their callbacks off the main actor, so these
// conformances are nonisolated and hop back to the main actor to resume the waiter.
extension VoiceOutput: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finishSpeaking() }
    }
}

extension VoiceOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishSpeaking() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishSpeaking() }
    }
}
