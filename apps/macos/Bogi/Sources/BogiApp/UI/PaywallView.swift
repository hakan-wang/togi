import SwiftUI

/// The Togi Pro upsell. Shown when a free user spends their daily AI quota, or from the
/// menu. Rendering-only: the checkout / portal actions and the dismiss are injected so the
/// view stays decoupled from BillingClient and the app lifecycle (same pattern as LoginView).
struct PaywallView: View {
    /// Free calls used today and the daily limit, when known — tunes the headline.
    var usedToday: Int? = nil
    var dailyLimit: Int? = nil
    /// Opens Stripe Checkout for the chosen plan (monthly / annual).
    let startCheckout: (BillingClient.Plan) async -> Void
    /// Opens the Stripe Customer Portal to manage an existing subscription.
    var openPortal: () async -> Void = {}
    var onClose: () -> Void = {}

    @State private var annual = false
    @State private var working = false

    private let features = [
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
                    .frame(width: 96, height: 96)
                Text(headline)
                    .font(.title3).bold()
                    .multilineTextAlignment(.center)
                Text("Let Togi run your whole day, not just sit with you for it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Picker("", selection: $annual) {
                Text("Monthly").tag(false)
                Text("Yearly").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(spacing: 2) {
                Text(annual ? "$79" : "$9.99")
                    .font(.system(size: 34, weight: .bold))
                Text(annual ? "per year · save 33%" : "per month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BogiColor.primary)
                            .font(.system(size: 13))
                        Text(feature).font(.subheadline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: upgrade) {
                if working {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Upgrade to Togi Pro").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working)

            Text("14-day money-back guarantee. Cancel anytime.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Button("Maybe later", action: onClose)
                    .buttonStyle(.link)
                Button("Manage subscription") { Task { await openPortal() } }
                    .buttonStyle(.link)
            }
            .font(.caption)
        }
        .padding(34)
        // Sized to feel like the onboarding pop-up (560x640 window) — a warm, familiar
        // moment that invites the upgrade rather than a small, surprising wall.
        .frame(width: 460)
    }

    /// When the user just hit the wall, name it; otherwise lead with the upgrade.
    private var headline: String {
        if let used = usedToday, let limit = dailyLimit, used >= limit {
            return "You and Togi got \(limit) things done today"
        }
        return "Want Togi for the whole day?"
    }

    private func upgrade() {
        working = true
        Task {
            await startCheckout(annual ? .annual : .monthly)
            working = false
        }
    }
}

#if DEBUG
#Preview("Paywall — quota hit") {
    PaywallView(usedToday: 5, dailyLimit: 5, startCheckout: { _ in }, openPortal: {}, onClose: {})
        .background(Color(white: 0.12))
}
#endif
