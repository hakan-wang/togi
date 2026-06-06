import SwiftUI

/// Blunt-coach chat surface. Rendering-only: the actual ask goes through the injected
/// `ask` closure so this view has no knowledge of the LLM/service layer.
struct CoachView: View {
    /// Sends the user's message and returns the coach's reply. Injected by the host.
    let ask: (String) async throws -> String

    @State private var messages: [(role: String, text: String)] = []
    @State private var input: String = ""
    @State private var sending: Bool = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            composer
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        Text("Ask Bogi anything. It won't flatter you.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)
                    }

                    ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                        MessageBubble(role: message.role, text: message.text)
                            .id(index)
                    }

                    if sending {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Bogi is thinking…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .id("typing")
                    }
                }
                .padding(12)
            }
            .onChange(of: messages.count) { _ in
                withAnimation { proxy.scrollTo(messages.count - 1, anchor: .bottom) }
            }
            .onChange(of: sending) { isSending in
                if isSending { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                TextField("Talk to Bogi…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit(submit)
                    .disabled(sending)

                Button(action: submit) {
                    Image(systemName: "paperplane.fill")
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!canSend)
            }
        }
        .padding(12)
    }

    private var canSend: Bool {
        !sending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }

        messages.append((role: "user", text: text))
        input = ""
        errorText = nil
        sending = true

        Task {
            do {
                let reply = try await ask(text)
                messages.append((role: "coach", text: reply))
            } catch {
                errorText = "Bogi couldn't answer: \(error.localizedDescription)"
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
                .background(bubbleStyle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                .multilineTextAlignment(.leading)

            if !isUser { Spacer(minLength: 32) }
        }
    }

    private var bubbleStyle: AnyShapeStyle {
        isUser ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.thinMaterial)
    }
}

#if DEBUG
#Preview("Coach chat") {
    CoachView(ask: { question in
        try? await Task.sleep(nanoseconds: 600_000_000)
        return "You asked “\(question)”. Stop stalling and open the deck — you've spent 73 minutes on social today."
    })
    .frame(width: 320, height: 480)
}
#endif
