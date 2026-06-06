import AppKit
import SwiftUI
import AuthenticationServices

/// Drives the eight-step first-run flow. Owns the user's in-progress answers and is the only place
/// that touches services — the views stay rendering-only, matching the rest of the app's UI layer.
@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published var name: String
    @Published var northStarText: String = ""
    @Published var northStarWhy: String = ""
    @Published var rhythm: CheckInRhythm = .both
    @Published var calendarConnected = false
    @Published var accessibilityGranted: Bool
    @Published var consentChecked: Bool
    @Published var busy = false
    @Published var errorText: String?

    /// The name pre-filled from the account, if any. Drives "is this right?" vs "what should I call you?".
    let prefilledName: String?

    /// Set by OnboardingWindow; used as the OAuth presentation anchor.
    weak var hostWindow: NSWindow?

    private let northStar: NorthStarService
    private let capture: CaptureController
    private let planner: PlannerService
    private let googleCalendar: GoogleCalendarService
    private let settings: SettingsStore
    private let auth: SupabaseAuth
    private let notifications: NotificationAuthorizer
    private let onFinish: () -> Void

    init(northStar: NorthStarService,
         capture: CaptureController,
         planner: PlannerService,
         googleCalendar: GoogleCalendarService,
         settings: SettingsStore,
         auth: SupabaseAuth,
         notifications: NotificationAuthorizer,
         onFinish: @escaping () -> Void) {
        self.northStar = northStar
        self.capture = capture
        self.planner = planner
        self.googleCalendar = googleCalendar
        self.settings = settings
        self.auth = auth
        self.notifications = notifications
        self.onFinish = onFinish

        let identity = auth.cachedIdentity()
        self.prefilledName = identity.name
        self.name = identity.name ?? ""
        self.accessibilityGranted = capture.permissionState == .granted
        self.consentChecked = PrivacyConsent.isAccepted(settings)
    }

    // MARK: - Navigation

    func advance() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { step = next }
        } else {
            finish()
        }
    }

    func skip() { advance() }

    // MARK: - Step actions

    /// Record the user's acceptance of the current privacy policy, then move on. This is the gate
    /// that `startNormalRuntime` checks before capture is ever allowed to start.
    func acceptConsent() {
        PrivacyConsent.accept(settings)
        consentChecked = true
        advance()
    }

    func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { settings.set("user_display_name", trimmed) }
        advance()
    }

    func saveNorthStar() {
        let text = northStarText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { advance(); return }
        let why = northStarWhy.trimmingCharacters(in: .whitespaces)
        northStar.save(text: text, why: why.isEmpty ? nil : why)
        advance()
    }

    func connectCalendar() async {
        guard !busy else { return }
        busy = true
        errorText = nil
        do {
            // Loopback OAuth (Erik's flow): opens the default browser, no in-app web sheet needed.
            try await googleCalendar.authorize(clientId: GoogleConfig.clientID, clientSecret: GoogleConfig.clientSecret)
            settings.setBool("google_connected", true)
            NSApp.activate(ignoringOtherApps: true)
            calendarConnected = true
            busy = false
            advance()
        } catch {
            busy = false
            errorText = "Couldn't connect to Google. Try again, or connect later."
        }
    }

    func requestAccessibility() {
        capture.requestPermission()
    }

    /// Polled by the Accessibility screen so it can flip to "you're all set" the moment the grant lands.
    func refreshAccessibilityState() {
        accessibilityGranted = capture.permissionState == .granted
    }

    func requestNotifications() async {
        _ = await notifications.request()
        advance()
    }

    func saveRhythm() {
        settings.set("checkin_rhythm", rhythm.rawValue)
        advance()
    }

    func createFirstBlock() {
        let (start, end) = Self.firstBlockSlot()
        let title = northStarText.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Focus block"
            : "Focus: \(northStarText)"
        planner.createLocalBlock(title: title, start: start, end: end, category: nil)
        finish()
    }

    func finish() {
        settings.setBool("onboarding_completed", true)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty { settings.set("user_display_name", trimmedName) }
        settings.set("checkin_rhythm", rhythm.rawValue)
        onFinish()
    }

    /// Tomorrow 14:00 for 90 minutes — a concrete, plausible first protected block.
    private static func firstBlockSlot() -> (Date, Date) {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let start = cal.date(bySettingHour: 14, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return (start, start.addingTimeInterval(90 * 60))
    }
}
