import SwiftUI

/// Drives the launch gate: holds the current GateState, runs the strict online check, and
/// exposes sign-in. The AppDelegate observes `state` to decide whether to show the gate
/// window or start the main experience.
@MainActor
final class GateController: ObservableObject {
    @Published private(set) var state: GateState = .checking

    private let auth: SupabaseAuth
    private let gate: AccountGate
    private var checkTask: Task<Void, Never>?

    init(auth: SupabaseAuth, gate: AccountGate) {
        self.auth = auth
        self.gate = gate
    }

    /// Re-run the subscription check and publish the resulting state. Cancels any in-flight
    /// check so the most recent refresh wins (foreground/background can fire these rapidly).
    func refresh() async {
        checkTask?.cancel()
        let task = Task {
            state = .checking
            let outcome = await gate.check()
            guard !Task.isCancelled else { return }
            state = GateState(for: outcome)
        }
        checkTask = task
        await task.value
    }

    func signIn(email: String, password: String) async throws {
        try await auth.signIn(email: email, password: password)
        await refresh()
    }

    func signOut() {
        auth.signOut()
        state = .needsLogin
    }
}
