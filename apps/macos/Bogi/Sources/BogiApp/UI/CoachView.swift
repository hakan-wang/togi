import SwiftUI
import Combine

/// Blunt-coach chat surface, laid out as a command bar: the input sits on top, and the
/// conversation unfolds beneath it so the card can grow downward from almost nothing.
/// Empty state shows tappable, data-driven openers instead of dead space. Rendering-only:
/// the `ask` and `suggest` closures are injected by the host so this view never touches
/// the LLM or data layer.
struct CoachView: View {
    /// Sends the user's message and returns the coach's reply. Injected by the host.
    let ask: (String) async throws -> String
    /// Live conversation openers for the empty state. Injected by the host.
    var suggest: () -> [String] = { [] }
    /// Ceiling for the transcript before it scrolls internally, so the card never runs off
    /// the screen. Supplied by the host from the panel's max height.
    var transcriptMaxHeight: CGFloat = 420
    /// Pre-seeded transcript, used only by previews and the screenshot demo hook. Empty in
    /// the real app, where the conversation always starts fresh.
    var seedMessages: [(role: String, text: String)] = []
    /// Hands-free voice scheduling. Injected by the host; nil in previews/demo, where the mic
    /// button and the voice strip are simply hidden.
    var voice: VoiceSession? = nil

    @State private var messages: [(role: String, text: String)] = []
    @State private var input: String = ""
    @State private var sending: Bool = false
    @State private var errorText: String?
    @State private var suggestions: [String] = []
    /// Latches true once the transcript would overflow the cap, switching to a scroll view.
    @State private var overflowing = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            composer
            if let voice { VoiceStrip(voice: voice) }
            if messages.isEmpty {
                if !suggestions.isEmpty { openers }
            } else {
                transcript
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .onAppear {
            if messages.isEmpty, !seedMessages.isEmpty { messages = seedMessages }
            if suggestions.isEmpty { suggestions = suggest() }
            // Land the cursor in the field so you can type the moment the card appears.
            DispatchQueue.main.async { inputFocused = true }
        }
        // Each time the panel is shown, reset to a fresh, small chat (in place, no remount,
        // so the height machinery keeps working) with openers recomputed from the latest data.
        .onReceive(NotificationCenter.default.publisher(for: .companionDidOpen)) { _ in
            input = ""
            errorText = nil
            sending = false
            overflowing = false
            messages = seedMessages
            suggestions = suggest()
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    // MARK: - Composer (the command bar)

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                TextField("talk to togi…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit(submit)
                    .disabled(sending)

                if let voice { VoiceMicButton(voice: voice, disabled: sending) }
                sendButton
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1))
        }
    }

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(canSend ? BogiColor.primary : Color.gray.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!canSend)
    }

    // MARK: - Openers (empty-state suggestions)

    private var openers: some View {
        VStack(spacing: 6) {
            ForEach(suggestions, id: \.self) { text in
                Button { send(text) } label: {
                    HStack(spacing: 8) {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(BogiColor.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Transcript

    /// While the conversation fits, the messages render directly and the card grows to them
    /// (measured naturally — no ScrollView in the loop, so the height is reliable). Once they
    /// would overflow the cap we latch into a fixed-height scroll view that pins to the
    /// newest message, so the card never runs off the screen.
    private var transcript: some View {
        Group {
            if overflowing {
                ScrollViewReader { proxy in
                    ScrollView { messagesStack }
                        .frame(height: transcriptMaxHeight)
                        .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                        .onChange(of: messages.count) { _, _ in
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .onChange(of: sending) { _, _ in
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                }
            } else {
                messagesStack
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: TranscriptHeightKey.self, value: geo.size.height)
                        }
                    )
            }
        }
        .onPreferenceChange(TranscriptHeightKey.self) { height in
            if height > transcriptMaxHeight + 1 { overflowing = true }
        }
    }

    private var messagesStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                MessageBubble(role: message.role, text: message.text)
                    .id(index)
            }

            if sending {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("togi is thinking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Color.clear.frame(height: 1).id("bottom")
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sending

    private var canSend: Bool {
        !sending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() { send(input) }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }

        withAnimation(.easeInOut(duration: 0.28)) {
            messages.append((role: "user", text: text))
        }
        input = ""
        errorText = nil
        sending = true

        Task {
            do {
                let reply = try await ask(text)
                withAnimation(.easeInOut(duration: 0.28)) {
                    messages.append((role: "coach", text: reply))
                }
            } catch {
                errorText = "togi couldn't answer: \(error.localizedDescription)"
            }
            sending = false
        }
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let role: String
    let text: String

    private var isUser: Bool { role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 32) }

            Text(text)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubble, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(isUser ? 0 : 0.45), lineWidth: 1)
                )
                .foregroundStyle(isUser ? Color.white : BogiColor.ink)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                .multilineTextAlignment(.leading)

            if !isUser { Spacer(minLength: 32) }
        }
    }

    // Coach replies get a near-opaque light fill (not glass-on-glass) so the text stays
    // readable over any desktop, dark wallpapers included. User bubbles ride the sky accent.
    private var bubble: AnyShapeStyle {
        isUser ? AnyShapeStyle(BogiColor.primary) : AnyShapeStyle(BogiColor.background.opacity(0.92))
    }
}

/// Reports the natural height of the transcript content so the card can size to it.
private struct TranscriptHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

#if DEBUG
#Preview("Coach chat") {
    CoachView(
        ask: { question in
            try? await Task.sleep(nanoseconds: 600_000_000)
            return "you asked “\(question)”. stop stalling and open the deck — you've spent 73 minutes on social today."
        },
        suggest: {
            ["why did i lose 41 min to social?", "where did my time go today?", "plan my next hour"]
        }
    )
    .frame(width: 420)
    .padding(40)
    .background(Color.black)
}
#endif
