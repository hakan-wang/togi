import Foundation

/// Decides which surfaces must never be captured. The matching core
/// (`isExcluded`) is pure and AppKit-free so it can be unit-tested directly; the
/// capture service feeds it the frontmost app's bundle id, the focused window
/// title and (best-effort) the active web domain.
///
/// Ships sensible defaults — known password managers, banking/finance domains,
/// private/incognito windows and the system authentication agent — and lets the
/// user extend both the bundle-id and domain lists at runtime.
struct CaptureExcludes {
    /// Bundle ids that are always excluded regardless of user settings.
    static let defaultBundleIds: Set<String> = [
        // Password managers.
        "com.1password.1password",          // 1Password 8
        "com.agilebits.onepassword7",       // 1Password 7
        "com.agilebits.onepassword4",       // 1Password 6/7 legacy
        "com.sissolabs.passwords",
        "com.lastpass.LastPass",
        "in.sinew.Walletx",                 // Enpass
        "com.mrgeckosmedia.Enpass",
        "org.keepassxc.keepassxc",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal",
        "com.callpod.KeeperDesktop",
        "com.apple.keychainaccess",         // Keychain Access
        // System authentication / security dialogs.
        "com.apple.SecurityAgent",
        "com.apple.security.authhost",
        "com.apple.CoreAuthUI",
    ]

    /// Registrable domains (and their subdomains) excluded by default. Banking /
    /// finance surfaces where verbatim text capture would be especially
    /// sensitive.
    static let defaultDomains: Set<String> = [
        "chase.com",
        "bankofamerica.com",
        "wellsfargo.com",
        "citibank.com",
        "citi.com",
        "capitalone.com",
        "usbank.com",
        "pnc.com",
        "ally.com",
        "americanexpress.com",
        "discover.com",
        "paypal.com",
        "venmo.com",
        "stripe.com",
        "coinbase.com",
        "fidelity.com",
        "schwab.com",
        "vanguard.com",
        "robinhood.com",
        "revolut.com",
        "wise.com",
        "monzo.com",
        "n26.com",
        "hsbc.com",
        "barclays.co.uk",
    ]

    /// Case-insensitive markers that indicate a private/incognito browser window.
    /// Matched against the window title across Safari, Chrome, Edge, Firefox,
    /// Brave, Arc, etc.
    static let incognitoMarkers: [String] = [
        "incognito",
        "private browsing",
        "(private)",
        "private window",
        "inprivate",
    ]

    private(set) var userBundleIds: Set<String>
    private(set) var userDomains: Set<String>

    init(userBundleIds: Set<String> = [], userDomains: Set<String> = []) {
        self.userBundleIds = userBundleIds
        self.userDomains = Self.normalizeDomains(userDomains)
    }

    // MARK: - User controls

    mutating func excludeApp(bundleId: String) {
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userBundleIds.insert(trimmed)
    }

    mutating func unexcludeApp(bundleId: String) {
        userBundleIds.remove(bundleId.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    mutating func excludeDomain(_ domain: String) {
        guard let normalized = Self.normalizeDomain(domain) else { return }
        userDomains.insert(normalized)
    }

    mutating func unexcludeDomain(_ domain: String) {
        guard let normalized = Self.normalizeDomain(domain) else { return }
        userDomains.remove(normalized)
    }

    // MARK: - Pure matching core

    /// Whether the given surface must be excluded from capture. All arguments are
    /// optional because the capture service may not always resolve every field
    /// (e.g. a non-browser app has no domain).
    func isExcluded(appBundleId: String?, windowTitle: String?, domain: String?) -> Bool {
        if let bundleId = appBundleId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleId.isEmpty,
           Self.defaultBundleIds.contains(bundleId) || userBundleIds.contains(bundleId) {
            return true
        }

        if let domain = Self.normalizeDomain(domain ?? ""),
           matchesExcludedDomain(domain) {
            return true
        }

        if let title = windowTitle?.lowercased(),
           Self.incognitoMarkers.contains(where: { title.contains($0) }) {
            return true
        }

        return false
    }

    /// True when `domain` equals or is a subdomain of any excluded domain.
    private func matchesExcludedDomain(_ domain: String) -> Bool {
        let all = Self.defaultDomains.union(userDomains)
        for excluded in all where Self.domain(domain, matchesOrIsSubdomainOf: excluded) {
            return true
        }
        return false
    }

    // MARK: - Domain helpers (pure, testable)

    /// `a.b.example.com` matches `example.com`; `notexample.com` does not.
    static func domain(_ candidate: String, matchesOrIsSubdomainOf base: String) -> Bool {
        if candidate == base { return true }
        return candidate.hasSuffix("." + base)
    }

    /// Lowercases, strips a scheme/path if a full URL was passed, and removes a
    /// leading `www.`. Returns nil for empty input.
    static func normalizeDomain(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }

        if let url = URL(string: value), let host = url.host, !host.isEmpty {
            value = host
        } else {
            // Strip scheme manually if URL parsing didn't yield a host.
            if let schemeRange = value.range(of: "://") {
                value = String(value[schemeRange.upperBound...])
            }
            // Drop any path / query / port.
            if let slash = value.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == ":" }) {
                value = String(value[..<slash])
            }
        }

        if value.hasPrefix("www.") {
            value = String(value.dropFirst("www.".count))
        }
        return value.isEmpty ? nil : value
    }

    private static func normalizeDomains(_ raw: Set<String>) -> Set<String> {
        Set(raw.compactMap(normalizeDomain))
    }
}
