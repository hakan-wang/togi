import Foundation

/// Tracks the macOS permissions Bogi needs. Accessibility is the highest-risk
/// onboarding step (the spec cites ~40% drop) and is requested just-in-time.
/// EventKit and Microphone are requested in-context by their feature modules.
enum PermissionStatus: String {
    case notDetermined
    case granted
    case denied
}

struct PermissionSnapshot: Equatable {
    var accessibility: PermissionStatus
    var calendar: PermissionStatus
    var microphone: PermissionStatus

    static let unknown = PermissionSnapshot(
        accessibility: .notDetermined,
        calendar: .notDetermined,
        microphone: .notDetermined
    )

    /// Capture can run as soon as Accessibility is granted; other permissions
    /// only gate their own features.
    var captureReady: Bool { accessibility == .granted }
}
