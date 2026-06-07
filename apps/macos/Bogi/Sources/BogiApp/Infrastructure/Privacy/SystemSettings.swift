import AppKit

/// Opens a specific pane in macOS System Settings (formerly System Preferences).
///
/// The `x-apple.systempreferences:` pane identifiers are undocumented and have changed across macOS
/// releases (Ventura renamed several to `*-Settings.extension`), so each pane lists its URLs
/// newest-first and we open the first that succeeds. This is best-effort and side-effect-only: it
/// never throws and never crashes, and returns whether a pane opened so callers can react.
enum SystemSettings {
    enum Pane {
        case notifications
        case accessibility
    }

    @discardableResult
    @MainActor
    static func open(_ pane: Pane) -> Bool {
        for string in urlStrings(for: pane) {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return true }
        }
        return false
    }

    private static func urlStrings(for pane: Pane) -> [String] {
        switch pane {
        case .notifications:
            var urls: [String] = []
            // When we have a bundle id, deep-link straight to this app's row (Ventura+).
            if let id = Bundle.main.bundleIdentifier {
                urls.append("x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")
            }
            urls.append("x-apple.systempreferences:com.apple.Notifications-Settings.extension") // Ventura+
            urls.append("x-apple.systempreferences:com.apple.preference.notifications")          // Monterey-
            return urls
        case .accessibility:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            ]
        }
    }
}
