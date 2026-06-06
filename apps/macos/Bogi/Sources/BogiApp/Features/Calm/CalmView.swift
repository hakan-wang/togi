import SwiftUI

/// How the calm overlay opens.
enum CalmStart: Equatable {
    case breathe              // straight into paced breathing
    case offer                // a gentle "want a breath?" first, then breathing
    case intent(app: String)  // a pause before a distracting app: "what are you here to do?"
}

/// The "take a breath" calm overlay. A constant dreamy-sky backdrop; the centre morphs
/// between a gentle offer, an intent prompt, a short settle, and full paced breathing.
/// Reuses the brand sky gradient, mascot art, and bob; respects Reduce Motion. The plush
/// Togi never diagnoses how you feel — it only offers a pause, on your terms.
struct CalmView: View {
    var onOpen: ((String) -> Void)?
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Stage { case offer, intent, settle, opened, breathing }

    @State private var stage: Stage
    @State private var orbScale: CGFloat = 0.82
    @State private var phaseText = ""
    @State private var running = false
    @State private var appeared = false
    @State private var settleCount = 4
    @State private var chosenIntent: String?
    @State private var soundOn = false
    @State private var pad = AmbientPad()

    private let appLabel: String

    init(start: CalmStart = .breathe, onOpen: ((String) -> Void)? = nil, onDone: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onDone = onDone
        let initialStage: Stage
        switch start {
        case .offer:           initialStage = .offer;     appLabel = ""
        case .intent(let app): initialStage = .intent;    appLabel = app
        case .breathe:         initialStage = .breathing; appLabel = ""
        }
        _stage = State(initialValue: initialStage)
    }

    // Paced breathing: 4s in, 2s hold, 6s out. The long exhale is the part that settles.
    private let phases: [(text: String, duration: Double, scale: CGFloat)] = [
        ("breathe in", 4.0, 1.18),
        ("hold", 2.0, 1.18),
        ("breathe out", 6.0, 0.80),
    ]

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                content
            }
            .padding(26)
        }
        .padding(16)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            if stage == .breathing { startBreathing() }
        }
        .onDisappear { running = false; pad.stop() }
    }

    // MARK: - Backdrop + header

    private var backdrop: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(BogiGradient.sky)
            .overlay(clouds)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Color(hex: 0x285078).opacity(0.28), radius: 30, y: 16)
    }

    private var clouds: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.55)).frame(width: 200, height: 200).blur(radius: 26).offset(x: -120, y: -160)
            Circle().fill(Color.white.opacity(0.40)).frame(width: 160, height: 160).blur(radius: 24).offset(x: 140, y: -100)
            Circle().fill(Color.white.opacity(0.35)).frame(width: 220, height: 220).blur(radius: 30).offset(x: 90, y: 180)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(BogiColor.primary).frame(width: 9, height: 9)
                Text("togi")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(BogiColor.ink.opacity(0.7))
            }
            Spacer()
            iconButton(soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", help: "ambient sound", action: toggleSound)
            iconButton("xmark", help: "close") { pad.stop(); onDone() }
        }
    }

    // MARK: - Stage content (each stage fills and self-centres)

    @ViewBuilder private var content: some View {
        switch stage {
        case .breathing: breathingContent
        case .offer:     offerContent
        case .intent:    intentContent
        case .settle:    settleContent
        case .opened:    openedContent
        }
    }

    private var breathingContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            orbStage(big: true)
            Spacer(minLength: 12)
            Text(phaseText.isEmpty ? "let's take a breath" : phaseText)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(BogiColor.ink.opacity(0.72))
                .animation(.easeInOut(duration: 0.4), value: phaseText)
            Spacer(minLength: 22)
            pillButton("i feel better", action: onDone)
            Spacer(minLength: 6)
        }
    }

    private var offerContent: some View {
        VStack(spacing: 15) {
            Spacer(minLength: 0)
            orbStage(big: false)
            Text("looks like that one got a bit intense. want to take a breath with me?")
                .font(.system(size: 16, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(BogiColor.ink.opacity(0.8))
                .frame(maxWidth: 300)
            HStack(spacing: 10) {
                pillButton("yes, let's breathe") { goBreathing() }
                softButton("not now", action: onDone)
            }
            Text("you're in control. you can turn these off anytime.")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(BogiColor.muted.opacity(0.85))
            Spacer(minLength: 0)
        }
    }

    private var intentContent: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            orbStage(big: false)
            Text("what are you here to do?")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(BogiColor.ink.opacity(0.82))
            Text("just name it. no judgment, no lock.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BogiColor.muted)
            VStack(spacing: 9) {
                HStack(spacing: 9) { chip("post for work"); chip("reply to a comment") }
                HStack(spacing: 9) { chip("look something up"); chip("just a break") }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
    }

    private var settleContent: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            orbStage(big: true)
            Text("\(settleCount)")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(BogiColor.primary)
                .contentTransition(.numericText())
            Text("one slow breath, then it's yours")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BogiColor.muted)
            Spacer(minLength: 0)
        }
    }

    private var openedContent: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            orbStage(big: false)
            Text("okay. \(appLabel) is yours.")
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(BogiColor.ink.opacity(0.82))
            HStack(spacing: 10) {
                pillButton("open \(appLabel)") { onOpen?(appLabel); onDone() }
                softButton("actually, not now", action: onDone)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Orb

    private func orbStage(big: Bool) -> some View {
        ZStack {
            Circle()
                .fill(BogiColor.mascotBlue.opacity(0.30))
                .frame(width: big ? 300 : 200, height: big ? 300 : 200)
                .blur(radius: 40)
                .scaleEffect(orbScale)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            BogiColor.mascotBlue.opacity(0.55),
                            BogiColor.mascotBlue.opacity(0.0),
                        ],
                        center: .center, startRadius: 4, endRadius: big ? 150 : 104
                    )
                )
                .frame(width: big ? 250 : 168, height: big ? 250 : 168)
                .scaleEffect(orbScale)
                .shadow(color: Color.white.opacity(0.55), radius: 34)
            Circle()
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: big ? 250 : 168, height: big ? 250 : 168)
                .scaleEffect(orbScale)
                .opacity(0.5)
            BogiAsset.mascot
                .resizable()
                .scaledToFit()
                .frame(width: big ? 132 : 90, height: big ? 132 : 90)
                .shadow(color: Color(hex: 0x285078).opacity(0.25), radius: 14, y: 10)
                .bob(distance: 6, duration: 3.0)
        }
        .frame(height: big ? 264 : 178)
    }

    // MARK: - Buttons

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 11)
                .background(BogiColor.primary.opacity(0.92), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func softButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BogiColor.ink.opacity(0.7))
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(Color.white.opacity(0.5), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String) -> some View {
        Button(action: { pickIntent(title) }) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(chosenIntent == title ? .white : BogiColor.ink.opacity(0.78))
                .padding(.horizontal, 15).padding(.vertical, 10)
                .background(chosenIntent == title ? BogiColor.primary : Color.white.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(BogiColor.primary.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BogiColor.ink.opacity(0.55))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Behaviour

    private func toggleSound() { soundOn = pad.toggle() }

    private func goBreathing() {
        withAnimation(.easeInOut(duration: 0.4)) { stage = .breathing }
        startBreathing()
    }

    private func pickIntent(_ title: String) {
        chosenIntent = title
        withAnimation(.easeInOut(duration: 0.4)) { stage = .settle }
        runSettle()
    }

    private func startBreathing() {
        guard !running else { return }
        running = true
        runPhase(0)
    }

    private func runPhase(_ i: Int) {
        guard running, stage == .breathing else { return }
        let p = phases[i % phases.count]
        phaseText = p.text
        withAnimation(.easeInOut(duration: reduceMotion ? 0.001 : p.duration)) { orbScale = p.scale }
        DispatchQueue.main.asyncAfter(deadline: .now() + p.duration) { runPhase(i + 1) }
    }

    private func runSettle() {
        settleCount = 4
        withAnimation(.easeInOut(duration: reduceMotion ? 0.001 : 3.4)) { orbScale = 1.18 }
        tickSettle()
    }

    private func tickSettle() {
        guard stage == .settle else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard stage == .settle else { return }
            withAnimation { settleCount -= 1 }
            if settleCount <= 0 {
                withAnimation(.easeInOut(duration: reduceMotion ? 0.001 : 1.2)) { orbScale = 0.82 }
                withAnimation(.easeInOut(duration: 0.4)) { stage = .opened }
            } else {
                tickSettle()
            }
        }
    }
}

#if DEBUG
#Preview("Breathing") {
    CalmView(start: .breathe, onDone: {}).frame(width: 460, height: 580)
}
#Preview("Offer") {
    CalmView(start: .offer, onDone: {}).frame(width: 460, height: 580)
}
#Preview("Intent gate") {
    CalmView(start: .intent(app: "tiktok"), onDone: {}).frame(width: 460, height: 580)
}
#endif
