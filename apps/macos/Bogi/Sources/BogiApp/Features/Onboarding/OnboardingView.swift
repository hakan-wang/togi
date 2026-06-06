import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Observable wrapper around the pure `OnboardingState` machine. SwiftUI screens
/// bind to `state.step`; user actions translate to `OnboardingEvent`s. All the
/// branching logic lives in `OnboardingState` (and is unit tested) — this type
/// only wires events to side effects (opening System Settings, signalling
/// completion).
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var state: OnboardingState

    /// Opens the Accessibility pane in System Settings (injectable for tests).
    private let openAccessibilitySettings: () -> Void
    /// Opens the paid-signup page on the website (injectable for tests).
    private let openPaywall: () -> Void
    /// Called once onboarding reaches the terminal `mascot` step.
    private let onComplete: () -> Void

    init(
        state: OnboardingState = OnboardingState(),
        openAccessibilitySettings: @escaping () -> Void = OnboardingModel.openSystemAccessibilitySettings,
        openPaywall: @escaping () -> Void = OnboardingModel.openWebsitePaywall,
        onComplete: @escaping () -> Void = {}
    ) {
        self.state = state
        self.openAccessibilitySettings = openAccessibilitySettings
        self.openPaywall = openPaywall
        self.onComplete = onComplete
    }

    var step: OnboardingStep { state.step }

    func send(_ event: OnboardingEvent) {
        state.apply(event)
        if state.isComplete { onComplete() }
    }

    // MARK: User intents

    func acknowledgePrivacy() { send(.acknowledgedPrivacy) }
    func didAuthenticate(paid: Bool) { send(.authenticated(paid: paid)) }
    func accessibilityResolved(_ status: PermissionStatus) { send(.accessibilityResolved(status)) }
    func continueWithoutAccessibility() { send(.skipAccessibility) }
    func openAccessibilityPane() { openAccessibilitySettings() }
    func goToPaywall() { openPaywall() }

    // MARK: Default side effects

    /// Deep link into System Settings → Privacy & Security → Accessibility.
    nonisolated static func openSystemAccessibilitySettings() {
        #if canImport(AppKit)
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    nonisolated static func openWebsitePaywall() {
        #if canImport(AppKit)
        if let url = URL(string: "https://bogi.app/subscribe") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

/// First-run onboarding container. Renders one screen per `OnboardingStep` and
/// routes button taps back through `OnboardingModel`.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack {
            switch model.step {
            case .privacyPromise:
                PrivacyPromiseScreen(model: model)
            case .login:
                LoginScreen(model: model)
            case .accessibilityPrimer:
                AccessibilityPrimerScreen(model: model)
            case .mascot:
                MascotReadyScreen()
            }
        }
        .frame(width: 460, height: 420)
        .padding(28)
        .animation(.default, value: model.step)
    }
}

// MARK: - Screens

private struct PrivacyPromiseScreen: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 16) {
            Text("🐟").font(.system(size: 56))
            Text("Bogi keeps your life data yours")
                .font(.title2).bold()
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                PromiseRow(symbol: "eye.slash", text: "Reads on-screen text only — never screenshots or screen recording.")
                PromiseRow(symbol: "internaldrive", text: "Everything is stored locally on your Mac. Nothing is uploaded or synced.")
                PromiseRow(symbol: "scissors", text: "The AI sees only small, bounded slices — never a stream of everything.")
            }
            Spacer()
            Button("Continue") { model.acknowledgePrivacy() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }
}

private struct PromiseRow: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
    }
}

private struct LoginScreen: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 48)).foregroundStyle(.tint)
            Text("Log in to your account")
                .font(.title2).bold()
            Text("Bogi is a paid app. Log in with the account you subscribed with.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            // Auth itself is owned by the Auth module (Phase 3); this screen
            // hands off to it and reports the result via `didAuthenticate`.
            Button("Log in") { model.didAuthenticate(paid: true) }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            Button("Don't have a subscription? Subscribe on the web") {
                model.goToPaywall()
            }
            .buttonStyle(.link)
        }
    }
}

private struct AccessibilityPrimerScreen: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "accessibility")
                .font(.system(size: 48)).foregroundStyle(.tint)
            Text("Let Bogi see what you're working on")
                .font(.title2).bold()
                .multilineTextAlignment(.center)
            Text("Bogi reads on-screen text via macOS Accessibility so it can notice what you're actually doing — no screenshots, ever. Grant Accessibility in System Settings, then come back.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Open Accessibility Settings") { model.openAccessibilityPane() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            Button("I've granted it") { model.accessibilityResolved(.granted) }
            Button("Skip for now") { model.continueWithoutAccessibility() }
                .buttonStyle(.link)
        }
    }
}

private struct MascotReadyScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("🐟").font(.system(size: 64))
            Text("You're all set!")
                .font(.title2).bold()
            Text("Bogi is now swimming in your menu bar. The mascot will gently nudge you when you drift from what you planned.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
