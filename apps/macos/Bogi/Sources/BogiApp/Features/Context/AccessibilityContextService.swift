import ApplicationServices

struct AccessibilitySnapshot: Equatable {
    let activeApp: String?
    let focusedWindowTitle: String?
    let textSummary: String
}

final class AccessibilityContextService {
    func permissionState() -> PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    func snapshot() -> AccessibilitySnapshot {
        AccessibilitySnapshot(
            activeApp: nil,
            focusedWindowTitle: nil,
            textSummary: ""
        )
    }
}
