import Foundation
import UserNotifications

/// The eight first-run beats, in order. Raw values drive the progress dots and navigation.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case name
    case northStar
    case calendar
    case accessibility
    case notifications
    case rhythm
    case magicMoment

    /// Steps the user may skip. The North Star is encouraged but never forced; Accessibility is
    /// the one the product really needs, but we still never hard-trap the user on it.
    var isSkippable: Bool {
        switch self {
        case .calendar, .notifications, .rhythm, .northStar: return true
        default: return false
        }
    }
}

/// How often Togi checks in. Stored as the raw string in settings ("checkin_rhythm").
enum CheckInRhythm: String, CaseIterable, Identifiable {
    case morning
    case evening
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning: return "morning plan"
        case .evening: return "evening review"
        case .both: return "both"
        }
    }
}

/// Onboarding-time configuration that isn't part of the core services.
enum OnboardingConfig {
    /// Google installed-app (Desktop / iOS) OAuth client ID. Public for the PKCE flow, no secret.
    /// Paste the real client ID from Google Cloud Console here to make the calendar step live.
    static let googleClientId = ""

    static var googleConfigured: Bool { !googleClientId.isEmpty }

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
