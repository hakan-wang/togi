import Foundation
import AVFoundation

/// Togi's spoken voice. Prefers a cloud voice when a key is configured — ElevenLabs first, then
/// OpenAI — and falls back to the built-in macOS speech synthesizer otherwise, so replies
/// work with no key at all and simply sound smoother once one is set.
///
/// Keys (env var → settings table): ElevenLabs `ELEVENLABS_API_KEY` / `elevenlabs_api_key`
/// (voice via `ELEVENLABS_VOICE_ID` / `elevenlabs_voice_id`); OpenAI `OPENAI_API_KEY` /
/// `openai_api_key` (voice via `OPENAI_TTS_VOICE` / `openai_tts_voice`, default "nova").
@MainActor
final class VoiceOutput: NSObject, ObservableObject {
    private let settings: SettingsStore
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isSpeaking = false
    /// Live amplitude of Togi's own voice (0…1) while a line plays, so the aura behind the
    /// axolotl can swell with what Togi is actually saying. 0 when silent.
    @Published private(set) var level: Float = 0
    private var meterTimer: Timer?
    /// Each cloud voice latches off after it fails once this session (bad/gated key, no quota,
    /// network) so we don't lag every line with a doomed call — a failure in one just falls
    /// through to the next. Reset on next launch, which retries each once. ElevenLabs is the
    /// preferred voice but is account-gated (free tier returns 401), so a failure there must NOT
    /// cost us the working OpenAI voice — hence separate latches, not one shared flag.
    private var elevenDisabledForSession = false
    private var openAIDisabledForSession = false

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

    private var openAIKey: String? {
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty { return env }
        if let stored = settings.string("openai_api_key"), !stored.isEmpty { return stored }
        return nil
    }

    private var openAIVoice: String {
        if let env = ProcessInfo.processInfo.environment["OPENAI_TTS_VOICE"], !env.isEmpty { return env }
        if let stored = settings.string("openai_tts_voice"), !stored.isEmpty { return stored }
        return "nova"   // warm, friendly default
    }

    private var openAIModel: String {
        if let stored = settings.string("openai_tts_model"), !stored.isEmpty { return stored }
        return "gpt-4o-mini-tts"
    }

    /// True when a cloud voice is wired up. Used only to tell the user which voice they'll hear.
    var usesPremiumVoice: Bool { openAIKey != nil || elevenKey != nil }

    // MARK: - Speak

    /// Speak `text` and return when it has finished playing. Safe to call repeatedly.
    func speak(_ text: String) async {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        stop()   // never talk over a previous line

        // ElevenLabs first (Togi's intended voice). If it fails — e.g. the account is still on the
        // free tier and returns 401 — fall through to OpenAI rather than the robotic Mac voice, so
        // the voice only gets *better* once ElevenLabs is unblocked, never worse in the meantime.
        if let key = elevenKey, !elevenDisabledForSession {
            if let data = try? await fetchElevenLabs(text: line, key: key), !data.isEmpty {
                await play(data); return
            }
            elevenDisabledForSession = true
        }
        if let key = openAIKey, !openAIDisabledForSession {
            if let data = try? await fetchOpenAI(text: line, key: key), !data.isEmpty {
                await play(data); return
            }
            openAIDisabledForSession = true
        }
        await speakWithApple(line)
    }

    /// Stop any in-flight speech immediately.
    func stop() {
        if let player { player.stop() }
        player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        finishSpeaking()
    }

    // MARK: - OpenAI

    private func fetchOpenAI(text: String, key: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": openAIModel,
            "voice": openAIVoice,
            "input": text,
            "response_format": "mp3"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw VoiceOutputError.badStatus(http.statusCode)
        }
        return data
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
            p.isMeteringEnabled = true
            player = p
            isSpeaking = true
            p.play()
            startMetering()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                self.continuation = c
            }
        } catch {
            // Couldn't decode/play the audio — fall back so the user still hears the line.
            await speakWithApple(String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Playback metering (drives the voice aura)

    /// Poll the player's output level while it speaks and publish a smoothed 0…1 `level`, so the
    /// glow behind the axolotl pulses with Togi's actual voice.
    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleLevel() }
        }
    }

    private func sampleLevel() {
        guard let player, player.isPlaying else { return }
        player.updateMeters()
        let db = player.averagePower(forChannel: 0)    // ~ -160 (silence) … 0 (loudest)
        let norm = max(0, min(1, (db + 45) / 45))       // floor around -45 dB
        level = level * 0.4 + norm * 0.6                // smooth so it breathes, not jitters
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        level = 0
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
        stopMetering()
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
