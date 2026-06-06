import SwiftUI

/// Shown to a signed-in user without an active subscription. Website-first: the subscribe
/// button opens the pricing page in the browser; payment completion arrives via the Stripe
/// webhook, so the gate re-checks when the app regains focus. Rendering-only: actions injected.
struct PaywallView: View {
    /// Opens the website pricing page in the browser.
    let onSubscribe: () -> Void
    /// Re-run the gate (e.g. after subscribing on the web and returning).
    var onRecheck: () -> Void = {}
    /// Sign out / use a different account.
    var onSignOut: () -> Void = {}

    private static let features = [
        "Always-on focus tracking, all day",
        "Automatic replanning when you fall behind",
        "Coaching that learns your patterns",
        "Unlimited nudges and focus blocks",
    ]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                BogiAsset.mascot
                    .resizable().scaledToFit()
                    .frame(width: 54, height: 54)
                Text("Subscribe to unlock Togi")
                    .font(.title3).bold()
                    .multilineTextAlignment(.center)
                Text("Let Togi run your whole day, not just sit with you for it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.features, id: \.self) { feature in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BogiColor.primary)
                            .font(.system(size: 13))
                        Text(feature).font(.subheadline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onSubscribe) {
                Text("Subscribe on the website").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("I've subscribed — check again", action: onRecheck)
                .buttonStyle(.link)
                .font(.caption)

            Button("Sign out", action: onSignOut)
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(26)
        .frame(width: 340)
    }
}

#if DEBUG
#Preview("Subscribe") {
    PaywallView(onSubscribe: {}, onRecheck: {}, onSignOut: {})
        .background(Color(white: 0.12))
}
#endif
