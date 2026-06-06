import SwiftUI

/// Chat UI for the blunt coach. Anchored to the mascot during integration
/// (mascot click / "Hey Bogi" opens this). The view is presentation-only; the
/// grounding + inference lives in `CoachService` via `CoachChatViewModel`.

struct CoachMessage: Identifiable, Equatable {
    enum Author: Equatable { case user, coach }
    let id = UUID()
    var author: Author
    var text: String
}

@MainActor
final class CoachChatViewModel: ObservableObject {
    @Published var messages: [CoachMessage] = []
    @Published var draft: String = ""
    @Published var isThinking = false

    private let coach: CoachService

    init(coach: CoachService) {
        self.coach = coach
    }

    func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        draft = ""
        messages.append(CoachMessage(author: .user, text: question))
        isThinking = true
        Task { await ask(question) }
    }

    private func ask(_ question: String) async {
        defer { isThinking = false }
        do {
            let answer = try await coach.ask(question)
            messages.append(CoachMessage(author: .coach, text: answer))
        } catch {
            messages.append(CoachMessage(author: .coach, text: "I couldn't answer that: \(error)"))
        }
    }
}

struct CoachView: View {
    @StateObject private var model: CoachChatViewModel

    init(coach: CoachService) {
        _model = StateObject(wrappedValue: CoachChatViewModel(coach: coach))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.messages) { CoachBubble(message: $0) }
                        if model.isThinking {
                            Text("Bogi is thinking…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack {
                TextField("Ask Bogi about your time…", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .onSubmit { model.send() }
                Button("Ask") { model.send() }
                    .disabled(model.isThinking)
            }
            .padding()
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

private struct CoachBubble: View {
    let message: CoachMessage

    var body: some View {
        HStack {
            if message.author == .user { Spacer(minLength: 40) }
            Text(message.text)
                .padding(10)
                .background(background)
                .foregroundStyle(message.author == .user ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity, alignment: message.author == .user ? .trailing : .leading)
            if message.author == .coach { Spacer(minLength: 40) }
        }
        .id(message.id)
    }

    private var background: Color {
        message.author == .user ? Color.accentColor : Color.secondary.opacity(0.15)
    }
}
