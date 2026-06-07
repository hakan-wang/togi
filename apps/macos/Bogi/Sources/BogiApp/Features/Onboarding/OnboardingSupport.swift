import Foundation
import UserNotifications

/// The first-run beats, in order. Raw values drive the progress dots and navigation.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case name
    case northStar
    case accessibility
    case notifications
    case magicMoment

    /// Steps the user may skip. The North Star is encouraged but never forced; Accessibility is
    /// the one the product really needs, but we still never hard-trap the user on it.
    var isSkippable: Bool {
        switch self {
        case .notifications, .northStar: return true
        default: return false
        }
    }
}

/// Onboarding-time configuration that isn't part of the core services. Google OAuth now lives in
/// `GoogleConfig` (shared with the calendar sync coordinator), so it isn't duplicated here.
enum OnboardingConfig {
    /// Tappable starter goals on the North Star screen, to beat the blank-page freeze.
    static let northStarExamples = [
        "graduate without all-nighters",
        "ship my own thing",
        "get genuinely fit"
    ]
}

/// Thin wrapper over the notification permission request so the flow never dead-ends — or crashes.
///
/// `UNUserNotificationCenter.current()` asserts with an *uncatchable* `NSException`
/// ("bundleProxyForCurrentProcess is nil") unless the process is a real `.app` bundle, so a bare
/// `swift build` dev run would otherwise take the whole app down. Because the assertion fires inside
/// a `dispatch_once` block, `try`/`catch` can't save us — we must never call into the center outside
/// a bundle. So we (1) only touch the notification center inside a real `.app`, and (2) when we
/// can't prompt — unbundled, or the user already denied — redirect to System Settings instead.
@MainActor
final class NotificationAuthorizer {
    private let isBundledApp: () -> Bool
    private let openSettings: @MainActor () -> Void

    init(isBundledApp: @escaping () -> Bool = { Bundle.main.bundleURL.pathExtension == "app" },
         openSettings: @escaping @MainActor () -> Void = { SystemSettings.open(.notifications) }) {
        self.isBundledApp = isBundledApp
        self.openSettings = openSettings
    }

    /// Returns whether notifications are authorized. Never throws, never crashes, never dead-ends.
    @discardableResult
    func request() async -> Bool {
        guard isBundledApp() else {
            // Dev/unbundled: calling the notification center here would crash. Redirect instead.
            openSettings()
            return false
        }
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            // First run: this shows the native permission prompt ("Togi would like to send…").
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            if !granted { openSettings() }
            return granted
        case .denied:
            // Once denied, macOS won't prompt again — send the user straight to the toggle.
            openSettings()
            return false
        default:
            return true // authorized / provisional / ephemeral
        }
    }
}
