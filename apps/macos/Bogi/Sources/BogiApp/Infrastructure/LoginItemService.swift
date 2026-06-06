import Foundation
import ServiceManagement

/// Controls whether Togi launches automatically at login.
///
/// Uses the modern ServiceManagement API (`SMAppService`, macOS 13+). Registering the
/// main app adds it to System Settings → General → Login Items — no helper bundle, no
/// privileged install step. Calls are best-effort: in an unbundled dev build (`swift run`)
/// registration may fail, which we log and otherwise ignore.
enum LoginItemService {
    /// True when Togi is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister Togi as a login item. Returns the resulting enabled state.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                // Already enabled → nothing to do. `.requiresApproval` means the user
                // turned it off in System Settings; we don't fight that here.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Bogi: failed to set launch-at-login=\(enabled): \(error)")
        }
        return isEnabled
    }
}
