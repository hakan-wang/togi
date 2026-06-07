import Foundation
import Sparkle

/// Self-update wiring for Developer-ID (non-App-Store) distribution.
///
/// Wraps Sparkle's `SPUStandardUpdaterController`, which on launch reads `SUFeedURL`,
/// `SUPublicEDKey`, and `SUEnableAutomaticChecks` from Info.plist, fetches the appcast,
/// and (once a real EdDSA public key is in place) verifies + installs signed updates.
/// `canCheckForUpdates` is republished so the "Check for Updates…" menu item can disable
/// itself while a check is already running.
///
/// Distribution note: Sparkle is a dynamic framework. `Packaging/build-app.sh` embeds it
/// into `Contents/Frameworks` and signs the nested `Autoupdate`/`Updater.app`/XPC services
/// before the outer app, or it won't load (and notarization would reject the unsigned code).
@MainActor
final class UpdaterController: ObservableObject {
    /// True when a user-initiated check is allowed (false while one is in flight).
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true begins the background schedule immediately (governed by
        // SUEnableAutomaticChecks). Default delegates are fine — no custom feed logic.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Trigger a user-initiated update check (shows Sparkle's standard UI/progress).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
