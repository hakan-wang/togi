import Foundation
import Combine

/// Orchestrates a "talk to Togi" exchange. Two ways in: hold Control (push-to-talk — no window,
/// the floating axolotl IS the whole UI) or tap the chat mic. Either way: listen → understand →
/// schedule the event or ask a follow-up out loud, keeping context across turns. This is the
/// state machine the mascot glow + bubble (and the chat strip) observe.
@MainActor
final class VoiceSession: ObservableObject {
    enum Phase: Equatable {
        case idle          // not in a voice exchange
        case listening     // mic open, capturing speech (glow reacts)
        case thinking      // asked the brain, waiting
        case speaking      // Togi is talking (a question or a confirmation)
        case waiting       // Togi asked something; hold Control again to answer
        case scheduled     // an event was just created (Undo available in the chat)
        case chatting      // Togi answered a non-scheduling line
        case denied        // mic / speech / calendar permission missing
        case error         // something went wrong
    }

    /// A calendar event Togi just created, kept so the user can undo it. `source` records which
    /// backend it went to (Google vs Apple) so the undo deletes it from the right place.
    struct Scheduled: Equatable {
        let id: String
        let source: CalendarRouter.Source
        let title: String
        let start: Date
        let end: Date
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var togiLine: String = ""
    @Published private(set) var lastEvent: Scheduled?
    /// Live mic input level (0…1) for the reactive glow behind the axolotl.
    @Published private(set) var level: Float = 0

    var isMicActive: Bool { phase == .listening }
    var isActive: Bool { phase != .idle }

    private let recognizer = SpeechRecognizer()
    private let voice: VoiceOutput
    private let agent: VoiceCommandAgent
    private let calendar: CalendarRouter
    private var history: [VoiceCommandAgent.Turn] = []
    private var cancellables: Set<AnyCancellable> = []
    /// Push-to-talk (Control held) vs the tap mic in the chat — changes the follow-up behaviour.
    private var holdMode = false
    /// Whether Control is physically held right now (guards the first-run permission-prompt race).
    private var isHolding = false
    /// The hands-free voice overlay (tap Control): runs continuous turns with no window and
    /// dismisses itself once it books the event. False for the chat-strip mic, which keeps its
    /// scheduled card up for Undo.
    private var handsFree = false

    init(voice: VoiceOutput, agent: VoiceCommandAgent, calendar: CalendarRouter) {
        self.voice = voice
        self.agent = agent
        self.calendar = calendar

        recognizer.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self] text in self?.liveTranscript = text }
            .store(in: &cancellables)

        // While listening, the aura follows the mic. While Togi is speaking, it follows Togi's
        // own voice (playback meter). Each source only writes during its own phase so they don't
        // fight, and the result is one `level` the mascot glow reads either way.
        recognizer.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] lvl in
                guard let self, self.phase == .listening else { return }
                self.level = lvl
            }
            .store(in: &cancellables)

        voice.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] lvl in
                guard let self, self.phase == .speaking else { return }
                self.level = lvl
            }
            .store(in: &cancellables)
    }

    // MARK: - Push-to-talk (hold Control)

    /// Control pressed: start (or continue) recording. No window opens — the axolotl is the UI.
    func beginHold() {
        isHolding = true
        holdMode = true
        if phase != .waiting {        // a fresh request; a follow-up keeps the conversation
            history.removeAll()
            lastEvent = nil
        }
        togiLine = ""
        Task {
            let granted = await recognizer.requestAuthorization()
            guard granted else {
                phase = .denied
                togiLine = "i need microphone and speech access. turn them on in system settings."
                return
            }
            guard isHolding else { phase = .idle; return }   // released during the prompt
            beginListening(autoStop: false)
        }
    }

    /// Control released: stop recording and let Togi respond.
    func endHold() {
        isHolding = false
        if phase == .listening { recognizer.stop() }
    }

    // MARK: - Hands-free conversation (tap Control)

    /// Tap Control: start a hands-free conversation, or end the one in progress. No window —
    /// the floating axolotl is the whole UI. Once started, Togi and the user trade turns
    /// automatically (a pause ends each turn); it books the event and dismisses itself when done.
    func toggleConversation() {
        if isActive { cancel() } else { startHandsFree() }
    }

    private func startHandsFree() {
        handsFree = true
        holdMode = false
        history.removeAll()
        lastEvent = nil
        togiLine = ""
        Task {
            let granted = await recognizer.requestAuthorization()
            guard granted else {
                // Hands-free has no window, so a silent denial looks like "nothing happened".
                // Say it out loud (TTS needs no mic permission) so the reason is clear.
                let line = "i need microphone and speech access. turn them on in system settings, then tap control again."
                togiLine = line
                phase = .speaking
                await voice.speak(line)
                phase = .denied
                autoIdle(after: 6)
                return
            }
            beginListening()
        }
    }

    // MARK: - Tap mic (chat)

    func toggle() {
        switch phase {
        case .listening: recognizer.stop()
        case .thinking:  break
        case .speaking:  cancel()
        default:         startFresh()
        }
    }

    func startFresh() {
        holdMode = false
        handsFree = false
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

    // MARK: - Shared

    func cancel() {
        isHolding = false
        holdMode = false
        handsFree = false
        recognizer.abort()
        voice.stop()
        liveTranscript = ""
        level = 0
        togiLine = ""
        phase = .idle
    }

    func undo() {
        guard let event = lastEvent else { return }
        let booked = CalendarRouter.Booked(id: event.id, source: event.source)
        lastEvent = nil
        let line = "okay, i removed \(event.title)."
        togiLine = line
        Task {
            await calendar.delete(booked)
            phase = .speaking
            await voice.speak(line)
            phase = .idle
        }
    }

    // MARK: - The loop

    private func beginListening(autoStop: Bool = true) {
        phase = .listening
        liveTranscript = ""
        recognizer.start(autoStop: autoStop) { [weak self] final in
            self?.handleFinal(final)
        }
    }

    private func handleFinal(_ text: String) {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else {
            phase = .idle          // heard nothing — settle back to rest
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
                if handsFree { autoIdle(after: 6) }
            }
        }
    }

    private func process(_ decision: VoiceCommandAgent.Decision) async {
        switch decision {
        case let .needInfo(say):
            let line = say.isEmpty ? "which time?" : say
            history.append(.init(role: "togi", text: line))
            togiLine = line
            phase = .speaking
            await voice.speak(line)
            beginListening()               // keep the conversation going, hands-free

        case let .chat(say):
            let line = say.isEmpty ? "i'm here." : say
            history.append(.init(role: "togi", text: line))
            togiLine = line
            phase = .speaking
            await voice.speak(line)
            if handsFree {
                beginListening()           // hands-free: keep talking, no re-press
            } else {
                phase = .chatting
            }

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
        // When Google is connected we book straight to it and skip the Apple permission dance.
        // Otherwise Apple Calendar is the target, so make sure we have Calendar access first.
        if !calendar.googleConnected {
            if calendar.appleNeedsPermission() {
                _ = await calendar.requestAppleAccess()
            }
            guard calendar.appleAuthorized() else {
                let line = "i need calendar access to add that. turn it on in system settings, then ask me again."
                togiLine = line
                phase = .speaking
                await voice.speak(line)
                phase = .denied
                if handsFree { autoIdle(after: 6) }   // don't get stuck non-idle (a later tap would just cancel)
                return
            }
        }

        let booked: CalendarRouter.Booked
        do {
            booked = try await calendar.book(title: title, start: start, end: end, notes: "Added by Togi")
        } catch {
            let line = "hmm, i couldn't save that to your calendar."
            togiLine = line
            phase = .speaking
            await voice.speak(line)
            phase = .error
            if handsFree { autoIdle(after: 6) }
            return
        }

        lastEvent = Scheduled(id: booked.id, source: booked.source, title: title, start: start, end: end)
        let line = say.isEmpty ? "done, i've added \(title) to your calendar." : say
        history.append(.init(role: "togi", text: line))
        togiLine = line
        phase = .speaking
        await voice.speak(line)
        phase = .scheduled
        // Hands-free voice overlay: it's done — let the axolotl fade back to rest on its own.
        // Chat-strip mic keeps the scheduled card up so the user can Undo.
        if handsFree { autoIdle(after: 4) }
    }

    /// After a push-to-talk turn, fade the axolotl back to rest if nothing else happens.
    private func autoIdle(after seconds: Double) {
        let snapshot = phase
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if phase == snapshot {
                phase = .idle
                togiLine = ""
            }
        }
    }
}
