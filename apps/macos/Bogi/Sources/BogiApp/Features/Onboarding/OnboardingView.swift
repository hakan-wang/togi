import SwiftUI

/// The first-run flow: a frosted, mascot-led card that walks the user through the eight beats.
/// Rendering-only — every action is delegated to `OnboardingCoordinator`.
struct OnboardingView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    /// Drives the live "is Accessibility granted yet?" check on the primer screen.
    private let accessibilityTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            background
            VStack(spacing: 18) {
                header
                stepView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(28)
        }
        .frame(width: 560, height: 640)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        )
    }

    // MARK: - Chrome

    private var background: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            BogiGradient.sky.opacity(0.55)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("togi")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(BogiColor.ink)
            Spacer()
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Circle()
                        .fill(step.rawValue <= coordinator.step.rawValue
                              ? BogiColor.primary
                              : Color.white.opacity(0.6))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch coordinator.step {
        case .welcome: welcome
        case .name: nameStep
        case .northStar: northStarStep
        case .calendar: calendarStep
        case .accessibility: accessibilityStep
        case .notifications: notificationsStep
        case .rhythm: rhythmStep
        case .magicMoment: magicMomentStep
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            BogiAsset.mascot.resizable().scaledToFit().frame(width: 150, height: 150).bob()
            VStack(spacing: 8) {
                Text("Hi, I'm Togi.")
                    .font(.title).bold().foregroundStyle(BogiColor.ink)
                bodyText("I'm your accountability coach, and I live up here in your menu bar. Let's get me set up. It takes about a minute.")
            }
            Spacer()
            primaryButton("let's go") { coordinator.advance() }
        }
    }

    private var nameStep: some View {
        VStack(spacing: 20) {
            Spacer()
            heading("First things first.",
                    coordinator.prefilledName == nil
                        ? "What should I call you?"
                        : "I'll call you \(coordinator.prefilledName ?? ""). Did I get that right?")
            TextField("your name", text: $coordinator.name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .onSubmit { if canContinueName { coordinator.commitName() } }
            Spacer()
            primaryButton("that's me", enabled: canContinueName) { coordinator.commitName() }
        }
    }

    private var northStarStep: some View {
        VStack(spacing: 14) {
            heading("What's your North Star?",
                    "Your North Star is the one big thing your life is pointing at right now. It's the reason the small to-dos matter, and it's what I measure everything against. Pick one to start. You can change it whenever you want.")
            VStack(spacing: 8) {
                ForEach(OnboardingConfig.northStarExamples, id: \.self) { example in
                    Button { coordinator.northStarText = example } label: {
                        Text(example)
                            .font(.callout).foregroundStyle(BogiColor.ink)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.55), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(spacing: 8) {
                TextField("your North Star", text: $coordinator.northStarText)
                    .textFieldStyle(.roundedBorder)
                TextField("why does this matter to you? (optional)", text: $coordinator.northStarWhy)
                    .textFieldStyle(.roundedBorder)
            }
            Spacer(minLength: 4)
            primaryButton("set my North Star", enabled: hasNorthStar) { coordinator.saveNorthStar() }
            secondaryButton("skip for now") { coordinator.skip() }
        }
    }

    private var calendarStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 50)).foregroundStyle(BogiColor.primary)
            heading("Let's see where your time already goes.",
                    "Connect your calendar and I can show you what's already committed, then help you protect real time for your North Star. Your calendar stays on this Mac.")
            if let error = coordinator.errorText {
                Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            if !OnboardingConfig.googleConfigured {
                Text("calendar setup is being finalized — you can connect right after.")
                    .font(.caption).foregroundStyle(BogiColor.muted).multilineTextAlignment(.center)
            }
            Spacer()
            primaryButton(coordinator.busy ? "connecting…" : "connect google calendar",
                          enabled: OnboardingConfig.googleConfigured && !coordinator.busy) {
                Task { await coordinator.connectCalendar() }
            }
            secondaryButton("connect later") { coordinator.skip() }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: coordinator.accessibilityGranted ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 50))
                .foregroundStyle(coordinator.accessibilityGranted ? .green : BogiColor.primary)
            heading(coordinator.accessibilityGranted ? "You're all set." : "Here's how I actually watch your back.",
                    coordinator.accessibilityGranted
                        ? "Accessibility is on. I can see what you're working on now, and it all stays on this Mac."
                        : "To coach you, I read the text on your screen every few seconds. That's it, no screenshots, ever. What I read goes into a local vault that only you can open, and it never leaves this Mac. Password and sensitive fields are skipped automatically. macOS will ask for permission next.")
            Spacer()
            if coordinator.accessibilityGranted {
                primaryButton("continue") { coordinator.advance() }
            } else {
                primaryButton("open system settings") { coordinator.requestAccessibility() }
                secondaryButton("not now") { coordinator.skip() }
            }
        }
        .onReceive(accessibilityTimer) { _ in coordinator.refreshAccessibilityState() }
    }

    private var notificationsStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 50)).foregroundStyle(BogiColor.primary)
            heading("Let me speak up when it counts.",
                    "With notifications on, I can nudge you when you start to drift, and cheer you on when you stay on track. I'll keep it to what matters.")
            Spacer()
            primaryButton("turn on notifications") { Task { await coordinator.requestNotifications() } }
            secondaryButton("maybe later") { coordinator.skip() }
        }
    }

    private var rhythmStep: some View {
        VStack(spacing: 20) {
            Spacer()
            heading("When should we check in?",
                    "Pick the rhythm that fits you. We can plan the day in the morning, look back in the evening, or both. You can change this anytime.")
            Picker("", selection: $coordinator.rhythm) {
                ForEach(CheckInRhythm.allCases) { rhythm in
                    Text(rhythm.label).tag(rhythm)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 340)
            Spacer()
            primaryButton("set my rhythm") { coordinator.saveRhythm() }
        }
    }

    private var magicMomentStep: some View {
        VStack(spacing: 16) {
            Spacer()
            BogiAsset.mascot.resizable().scaledToFit().frame(width: 110, height: 110).bob()
            heading(coordinator.name.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "You're all set."
                        : "You're all set, \(coordinator.name).",
                    magicBody)
            Spacer()
            primaryButton("hold my first focus block") { coordinator.createFirstBlock() }
            secondaryButton("i'll start later") { coordinator.finish() }
            Text("I'm in your menu bar whenever you need me.")
                .font(.caption).foregroundStyle(BogiColor.muted)
        }
    }

    // MARK: - Helpers

    private var canContinueName: Bool {
        !coordinator.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasNorthStar: Bool {
        !coordinator.northStarText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var magicBody: String {
        if coordinator.northStarText.trimmingCharacters(in: .whitespaces).isEmpty {
            return "From now on, I'm here to keep your days pointed at what matters. Want to start now? Let's protect your first focus block."
        }
        return "From now on, I'm keeping your days pointed at \(coordinator.northStarText). Want to start now? Let's put your first focus block on the calendar and actually protect it."
    }

    private func heading(_ title: String, _ body: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2).bold().foregroundStyle(BogiColor.ink)
                .multilineTextAlignment(.center)
            bodyText(body)
        }
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.body).foregroundStyle(BogiColor.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(BogiColor.primary)
        .disabled(!enabled)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(BogiColor.muted)
    }
}
