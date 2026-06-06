import Foundation

/// Decides whether a snapshot must NOT be captured. Default-on sensitive surfaces plus
/// user-configured app/domain excludes. (Domain matching is best-effort from window
/// title + text until proper browser-URL reads land.)
final class CaptureExcludes {
    private let sensitiveBundleIds: Set<String>
    private let privateWindowMarkers: [String]
    private var excludedApps: Set<String>
    private var excludedDomains: [String]

    init(sensitiveBundleIds: Set<String>,
         privateWindowMarkers: [String],
         excludedApps: [String],
         excludedDomains: [String]) {
        self.sensitiveBundleIds = sensitiveBundleIds
        self.privateWindowMarkers = privateWindowMarkers
        self.excludedApps = Set(excludedApps)
        self.excludedDomains = excludedDomains.map { $0.lowercased() }
    }

    /// Default-on sensitive surfaces (password managers, system auth) + the user's lists.
    static func makeDefault(userApps: [String] = [], userDomains: [String] = []) -> CaptureExcludes {
        CaptureExcludes(
            sensitiveBundleIds: [
                "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword4",
                "com.bitwarden.desktop", "com.lastpass.lastpassmacdesktop", "com.dashlane.dashlanephonefinal",
                "in.sinew.Enpass-Desktop", "com.apple.keychainaccess", "com.apple.SecurityAgent"
            ],
            privateWindowMarkers: ["Private", "Incognito", "InPrivate"],
            excludedApps: userApps,
            excludedDomains: userDomains.isEmpty ? defaultSensitiveDomains : userDomains + defaultSensitiveDomains
        )
    }

    // Starter list (audience is Sweden first) — refined over time.
    static let defaultSensitiveDomains = [
        "nordea.", "swedbank.", "handelsbanken.", "seb.se", "icabanken.", "avanza.",
        "paypal.com", "chase.com", "bankofamerica.com", "wellsfargo."
    ]

    func addApp(_ bundleId: String) { excludedApps.insert(bundleId) }
    func addDomain(_ domain: String) { excludedDomains.append(domain.lowercased()) }

    func isExcluded(_ snap: CaptureSnapshot) -> Bool {
        if snap.hasSecureField { return true }
        if let id = snap.bundleId, sensitiveBundleIds.contains(id) || excludedApps.contains(id) { return true }
        if let title = snap.windowTitle, privateWindowMarkers.contains(where: { title.localizedCaseInsensitiveContains($0) }) {
            return true
        }
        let haystack = "\(snap.windowTitle ?? "") \(snap.text ?? "")".lowercased()
        if excludedDomains.contains(where: { haystack.contains($0) }) { return true }
        return false
    }
}
