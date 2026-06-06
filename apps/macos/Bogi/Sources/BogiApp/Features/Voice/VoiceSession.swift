import Foundation
import Combine

/// Orchestrates one hands-free "talk to Togi" exchange: listen → understand → either schedule
/// the event or ask a follow-up question out loud → listen again, until it has what it needs.
/// This is the state machine the voice UI observes; it owns the recognizer, the spoken voice,
/// the intent brain, and the calendar write, and exposes only published, render-ready state.
@MainActor
final class VoiceSession: ObservableObject {
    enum Phase: Equatable {
        case idle          // not in a voice exchange
        case listening     // mic open, capturing speech
        case thinking      // asked the brain, waiting
        case speaking      // Togi is talking (a question or a confirmation)
        case scheduled     // an event was just created (Undo available)
        case chatting      // Togi answered a non-scheduling line
        case denied        // mic / speech / calendar permission missing
        case error         // something went wrong
    }

    /// A calendar event Togi just created, kept so the user can undo it.
    struct Scheduled: Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var togiLine: String = ""
    @Published private(set) var lastEvent: Scheduled?

    /// True while the mic is open — drives the mic button's active look.
    var isMicActive: Bool { phase == .listening }
    /// True whenever a voice exchange is on screen (so the host can show the voice strip).
    var isActive: Bool { phase != .idle }

    private let recognizer = SpeechRecognizer()
    private let voice: VoiceOutput
    private let agent: VoiceCommandAgent
    private let eventKit: EventKitService
    private var history: [VoiceCommandAgent.Turn] = []
    private var cancellables: Set<AnyCancellable> = []

    init(voice: VoiceOutput, agent: VoiceCommandAgent, eventKit: EventKitService) {
        self.voice = voice
        self.agent = agent
        self.eventKit = eventKit

        // Mirror the recognizer's partial transcript so the UI can caption it live.
        recognizer.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self] text in self?.liveTranscript = text }
            .store(in: &cancellables)
    }

    // MARK: - Mic button

    /// Single entry point wired to the mic button — behaviour depends on where we are.
    func toggle() {
        switch phase {
        case .listening:
            recognizer.stop()            // user taps to finish talking early
        case .thinking:
            break                        // let the brain finish
        case .speaking:
            cancel()                     // stop Togi mid-sentence
        default:
            startFresh()                 // idle / scheduled / chatting / denied / error
        }
    }

    /// Begin a brand-new exchange (clears the prior conversation and any undo).
    func startFresh() {
        history.removeAll()
        lastEvent = nil
        togiLine = ""
        Task {
            let granted = await recognizer.requestAuthorization()
            guard granted else {
                phase = .denied
                togiLine = "i need microphone and speech access. turn them on in system settings, then tap the mic again."
                return
            }
            beginListening()
        }
    }

    /// Stop everything and return to rest.
    func cancel() {
        recognizer.abort()
        voice.stop()
        liveTranscript = ""
        phase = .idle
    }

    /// Remove the event Togi just created.
    func undo() {
        guard let event = lastEvent else { return }
        _ = eventKit.deleteEvent(identifier: event.id)
        lastEvent = nil
        let line = "okay, i removed \(event.title)."
        togiLine = line
        Task {
            phase = .speaking
            await voice.speak(line)
            phase = .idle
        }
    }

    // MARK: - The loop

    private func beginListening() {
        phase = .listening
        liveTranscript = ""
        recognizer.start { [weak self] final in
            self?.handleFinal(final)
        }
    }

    private func handleFinal(_ text: String) {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else {
            // Heard nothing — quietly return to rest rather than guessing.
            phase = .idle
            return
        }
        history.append(.init(role: "user", text: said))
        phase = .thinking
        Task {
            do {
                let decision = try await agent.decide(history: history)
                await process(decision)
            } catch {
                let line = "i couldn't reach my brain just now. try again in a moment."
                togiLine = line
                phase = .speaking
                await voice.speak(line)
                phase = .error
            }
        }
    }

    private func process(_ decision: VoiceCommandAgent.Decision) async {
        switch decision {
        case let .needInfo(say):
            let line = say.isEmpty ? "could you tell me a bit more?" : say
            history.append(.init(role: "togi", text: line))
            togiLine = line
            phase = .speaking
            await voice.speak(line)
            beginListening()

        case let .chat(say):
            let line = say.isEmpty ? "i'm here." : say
            history.append(.init(role: "togi", text: line))
            togiLine = line
            phase = .speaking
            await voice.speak(line)
            phase = .chatting

        case let .cancel(say):
            let line = say.isEmpty ? "okay, never mind." : say
            togiLine = line
            phase = .speaking
            await voice.speak(line)
            phase = .idle

        case let .schedule(title, start, end, say):
            await schedule(title: title, start: start, end: end, say: say)
        }
    }

    private func schedule(title: String, start: Date, end: Date, say: String) async {
        if eventKit.authorizationStatus() == .notDetermined {
            _ = await eventKit.requestAccess()
        }
        guard eventKit.authorizationStatus() == .granted else {
            let line = "i need calendar access to add that. turn it on in system settings, then ask me again."
            togiLine = line
            phase = .speaking
            await voice.speak(line)
            phase = .denied
            return
        }

        guard let id = eventKit.createEvent(title: title, start: start, end: end, notes: "Added by Togi") else {
            let line = "hmm, i couldn't save that to your calendar."
            togiLine = line
            phase = .speaking
            await voice.speak(line)
            phase = .error
            return
        }

        lastEvent = Scheduled(id: id, title: title, start: start, end: end)
        let line = say.isEmpty ? "done, i've added \(title) to your calendar." : say
        history.append(.init(role: "togi", text: line))
        togiLine = line
        phase = .speaking
        await voice.speak(line)
        phase = .scheduled
    }
}
