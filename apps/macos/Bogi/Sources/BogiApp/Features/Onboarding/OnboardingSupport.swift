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

/// Thin wrapper over the notification permission request so the flow never dead-ends on it.
@MainActor
final class NotificationAuthorizer {
    @discardableResult
    func request() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    continuation.resume(returning: granted)
                }
        }
    }
}
