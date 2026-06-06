import Foundation

/// Proactive "want a breath?" nudge driven by a *benign* signal: time elapsed since the
/// last breath while the user is active. No biometrics, no keystroke reading, no content.
/// This is the "you've been heads-down a while" companion, never an emotion guess — which
/// also keeps it clear of the EU AI Act's emotion-recognition rules.
final class CalmScheduler {
    private var timer: Timer?
    private var lastBreath = Date()
    private let interval: TimeInterval
    private let isPaused: () -> Bool
    private let onNudge: () -> Void

    /// - Parameters:
    ///   - interval: seconds of continuous active time before Togi offers a breath.
    ///   - isPaused: when true (capture paused), the clock resets and nothing fires.
    ///   - onNudge: called on the main thread to present the gentle offer.
    init(interval: TimeInterval, isPaused: @escaping () -> Bool, onNudge: @escaping () -> Void) {
        self.interval = interval
        self.isPaused = isPaused
        self.onNudge = onNudge
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isPaused() {
                self.lastBreath = Date()       // don't accumulate while paused
                return
            }
            if Date().timeIntervalSince(self.lastBreath) >= self.interval {
                self.lastBreath = Date()
                self.onNudge()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Reset the clock whenever a breath happens (offered, accepted, or summoned).
    func noteBreath() { lastBreath = Date() }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
