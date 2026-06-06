import SwiftUI

/// Drives the launch gate: holds the current GateState, runs the strict online check, and
/// exposes sign-in. The AppDelegate observes `state` to decide whether to show the gate
/// window or start the main experience.
@MainActor
final class GateController: ObservableObject {
    @Published private(set) var state: GateState = .checking

    private let auth: SupabaseAuth
    private let gate: AccountGate

    init(auth: SupabaseAuth, gate: AccountGate) {
        self.auth = auth
        self.gate = gate
    }

    /// Re-run the subscription check and publish the resulting state.
    func refresh() async {
        state = .checking
        let outcome = await gate.check()
        state = GateState(for: outcome)
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
