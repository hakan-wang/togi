import SwiftUI
import Combine
import MarkdownUI

/// Blunt-coach chat surface, laid out as a command bar: the input sits on top, and the
/// conversation unfolds beneath it so the card can grow downward from almost nothing.
/// Empty state shows tappable, data-driven openers instead of dead space. Rendering-only:
/// the `ask` and `suggest` closures are injected by the host so this view never touches
/// the LLM or data layer.
struct CoachView: View {
    /// Sends the user's message and returns the coach's reply. The `onToken` callback fires
    /// for each streamed token so the reply can render incrementally. Injected by the host.
    let ask: (_ question: String, _ onToken: @escaping (String) -> Void) async throws -> String
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
    /// Natural (unclipped) height of the transcript content, measured off-screen so the
    /// scroll view can be capped reliably even with markdown tables/lists in the bubbles.
    @State private var contentHeight: CGFloat = 0
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

    /// The transcript always lives inside a `ScrollView`, but the scroll view is sized to the
    /// content's natural height capped at `transcriptMaxHeight`. While the conversation is
    /// short the card grows to fit it exactly (no empty scroll gutter); once the content
    /// exceeds the cap the scroll view stops growing and the user can scroll up to read long
    /// tables, while new messages auto-scroll the newest content into view. The content height
    /// is measured off-screen via a preference so the cap is reliable even with markdown
    /// (tables/lists) inside the bubbles.
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                messagesStack
                    // Measure the content's natural height. The ScrollView always proposes
                    // an unbounded height to its content, so this reads the true unclipped
                    // height regardless of the (possibly capped) frame applied below.
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: TranscriptHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    )
            }
            // Give the ScrollView a definite height equal to its content, capped at the
            // ceiling. Below the cap the card grows to fit exactly (no empty gutter); at the
            // cap the scroll view stops growing and the content genuinely scrolls. (Using
            // `fixedSize` here would size the scroll view to its content and defeat scrolling.)
            .frame(height: min(max(contentHeight, 1), transcriptMaxHeight))
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(TranscriptHeightKey.self) { contentHeight = $0 }
            .onAppear { scrollToBottom(proxy, animated: false) }
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: sending) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        // Defer to the next runloop tick so the layout (and any freshly streamed text) has
        // settled before we pin to the bottom anchor.
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
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
            // Reserve a coach bubble that fills in as tokens stream.
            let replyIndex = messages.count
            var streamed = false
            do {
                let reply = try await ask(text) { token in
                    Task { @MainActor in
                        if !streamed {
                            streamed = true
                            sending = false
                            messages.append((role: "coach", text: token))
                        } else if replyIndex < messages.count {
                            messages[replyIndex].text += token
                        }
                    }
                }
                if streamed {
                    if replyIndex < messages.count { messages[replyIndex].text = reply }
                } else {
                    // Non-streaming backend: just show the final reply.
                    messages.append((role: "coach", text: reply))
                }
            } catch {
                errorText = "togi couldn't answer: \(error.localizedDescription)"
            }
            sending = false
        }
    }
}

// MARK: - Transcript height measurement

/// Carries the transcript content's natural (unclipped) height up to `CoachView`, so the
/// scroll view can be capped at `transcriptMaxHeight` while still hugging short chats.
private struct TranscriptHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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

            content
                // Take the full multi-line height instead of being compressed to one
                // truncated line when the host panel hasn't grown yet. Without this the
                // bubble shows only the first line + "…" (replies run to hundreds of chars).
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubble, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(isUser ? 0 : 0.45), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 32) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isUser {
            // User input is short, plain text — no markdown parsing needed.
            Text(text)
                .font(.callout)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.leading)
        } else {
            // Coach replies are GitHub-Flavored Markdown (bold, lists, tables). MarkdownUI
            // renders all of it; SwiftUI's Text(markdown:) can't do tables/lists.
            Markdown(text)
                .markdownTextStyle { ForegroundColor(BogiColor.ink) }
                .markdownTheme(.bogi)
                .tint(BogiColor.primary)
                .multilineTextAlignment(.leading)
        }
    }

    // Coach replies get a near-opaque light fill (not glass-on-glass) so the text stays
    // readable over any desktop, dark wallpapers included. User bubbles ride the sky accent.
    private var bubble: AnyShapeStyle {
        isUser ? AnyShapeStyle(BogiColor.primary) : AnyShapeStyle(BogiColor.background.opacity(0.92))
    }
}

// MARK: - Markdown theme

private extension Theme {
    /// Coach-bubble markdown styling: callout-sized ink text on the light bubble, with
    /// compact spacing so multi-paragraph replies and tables sit tight inside the bubble.
    static let bogi = Theme()
        .text {
            ForegroundColor(BogiColor.ink)
            FontSize(NSFont.preferredFont(forTextStyle: .callout).pointSize)
        }
        .link {
            ForegroundColor(BogiColor.primary)
        }
        .strong {
            FontWeight(.semibold)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.92))
            BackgroundColor(BogiColor.ink.opacity(0.06))
        }
        .paragraph { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.12))
                .markdownMargin(top: 0, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .table { configuration in
            configuration.label
                .markdownTableBorderStyle(.init(color: BogiColor.ink.opacity(0.18)))
                .markdownMargin(top: 4, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 { FontWeight(.semibold) }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
}

#if DEBUG
#Preview("Coach chat") {
    CoachView(
        ask: { question, _ in
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
