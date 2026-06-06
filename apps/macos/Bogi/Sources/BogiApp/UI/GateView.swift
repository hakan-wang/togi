import SwiftUI

/// Full-window gate shown before the app unlocks. Pure rendering — every action and the
/// current state are injected by the AppDelegate's gate controller.
struct GateView: View {
    let state: GateState
    let signIn: (String, String) async throws -> Void
    let openWebsite: () -> Void
    let onSubscribe: () -> Void
    let onRecheck: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        switch state {
        case .checking:
            VStack(spacing: 12) {
                ProgressView()
                Text("Checking your subscription…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(40).frame(width: 340)
        case .needsLogin:
            LoginView(signIn: signIn, openWebsite: openWebsite)
        case .needsSubscription:
            PaywallView(onSubscribe: onSubscribe, onRecheck: onRecheck, onSignOut: onSignOut)
        case .blocked:
            VStack(spacing: 14) {
                BogiAsset.mascot.resizable().scaledToFit().frame(width: 48, height: 48)
                Text("Can't reach Togi right now")
                    .font(.headline)
                Text("Check your connection and try again.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Retry", action: onRecheck)
                    .buttonStyle(.borderedProminent)
                Button("Sign out", action: onSignOut)
                    .buttonStyle(.link).font(.caption)
            }
            .padding(32).frame(width: 340)
        case .unlocked:
            EmptyView()
        }
    }
}
