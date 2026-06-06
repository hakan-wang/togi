import Foundation

/// The user's acceptance of the privacy policy, recorded *before* any screen capture runs.
///
/// Stored in the local `settings` key/value table, so no schema migration is needed. We keep the
/// accepted version (and a timestamp, for an audit trail). Bumping `currentVersion` re-gates
/// everyone at next launch, so a material change to the policy forces fresh, explicit consent.
///
/// `currentVersion` deliberately matches the "Last updated" date of the published policy at
/// heytogi.com/privacy — keep the two in lockstep whenever the policy changes.
enum PrivacyConsent {
    static let currentVersion = "2026-06-06"
    static let policyURL = URL(string: "https://heytogi.com/privacy")!

    private static let versionKey = "privacy_consent_accepted_version"
    private static let dateKey = "privacy_consent_accepted_at"

    /// True only if the user has accepted the *current* policy version.
    static func isAccepted(_ settings: SettingsStore) -> Bool {
        settings.string(versionKey) == currentVersion
    }

    /// Record acceptance of the current policy version, with a timestamp for the record.
    static func accept(_ settings: SettingsStore) {
        settings.set(versionKey, currentVersion)
        settings.set(dateKey, ISO8601DateFormatter().string(from: Date()))
    }
}
