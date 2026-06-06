import SwiftUI
import AppKit

/// Blocking screen shown when the user is signed in but not paid (gate state
/// `.needsPayment`). Subscriptions are managed on the Stripe-hosted page (the
/// app never handles card data); after paying, "I've subscribed — refresh"
/// re-checks `GET /v1/account/status`.
struct PaywallView: View {
    /// Stripe-hosted billing/checkout page. Provided by the integrator.
    let manageSubscriptionURL: URL
    /// Re-check paid status (wired to `AccountGate.refresh`).
    var onRefresh: () -> Void
    /// Sign out (wired to `AuthProviding.signOut`).
    var onSignOut: () -> Void
    /// Injectable for testing; defaults to opening in the user's browser.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("A subscription is required")
                    .font(.title2).bold()
                Text("Manage your \(AppMetadata.name) subscription on the website, then refresh.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                Button {
                    openURL(manageSubscriptionURL)
                } label: {
                    Text("Manage subscription on the website").frame(maxWidth: 320)
                }
                .buttonStyle(.borderedProminent)

                Button("I've subscribed — refresh", action: onRefresh)
                    .buttonStyle(.bordered)

                Button("Sign out", action: onSignOut)
                    .buttonStyle(.link)
            }
        }
        .padding(32)
        .frame(width: 420, height: 340)
    }
}
