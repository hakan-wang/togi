import Foundation

@MainActor
final class LockInController: ObservableObject {
    @Published private(set) var currentSession: LockInSession?

    var isActive: Bool {
        currentSession?.endedAt == nil && currentSession != nil
    }

    func start(blockID: String?) {
        currentSession = LockInSession(
            id: UUID().uuidString,
            blockID: blockID,
            startedAt: Date(),
            endedAt: nil,
            summary: nil
        )
    }

    func end(summary: String?) {
        guard var session = currentSession else { return }
        session.endedAt = Date()
        session.summary = summary
        currentSession = session
    }
}
