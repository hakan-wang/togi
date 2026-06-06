import Foundation

/// Orchestrates the 6-second capture loop: read → exclude → diff → store. Also runs
/// retention pruning. Tick logic is synchronous + injectable so it can be unit-tested
/// without real accessibility access.
final class CaptureController {
    private let provider: SnapshotProviding
    private let store: ObservationStore
    private let excludes: CaptureExcludes
    private let pruner: RetentionPruner
    private let settings: SettingsStore
    private let clock: () -> Date

    var isPaused: Bool = false
    private var lastHash: String?
    private var timer: DispatchSourceTimer?
    private var pruneTimer: DispatchSourceTimer?

    init(provider: SnapshotProviding,
         store: ObservationStore,
         excludes: CaptureExcludes,
         pruner: RetentionPruner,
         settings: SettingsStore,
         clock: @escaping () -> Date = { Date() }) {
        self.provider = provider
        self.store = store
        self.excludes = excludes
        self.pruner = pruner
        self.settings = settings
        self.clock = clock
    }

    func start() {
        pruneNow()
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 6, repeating: 6)
        t.setEventHandler { [weak self] in _ = self?.performTick() }
        t.resume()
        timer = t

        let p = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        p.schedule(deadline: .now() + 86_400, repeating: 86_400)  // first daily prune ~24h after launch
        p.setEventHandler { [weak self] in self?.pruneNow() }
        p.resume()
        pruneTimer = p
    }

    func stop() {
        timer?.cancel()
        timer = nil
        pruneTimer?.cancel()
        pruneTimer = nil
    }

    var permissionState: PermissionState {
        provider.permissionState()
    }

    func requestPermission() {
        provider.requestPermission()
    }

    /// One capture cycle. Returns true if an observation was stored.
    @discardableResult
    func performTick() -> Bool {
        guard !isPaused else { return false }
        guard provider.permissionState() == .granted else { return false }
        guard let snap = provider.snapshot() else { return false }
        if excludes.isExcluded(snap) { return false }
        if snap.contentHash == lastHash { return false }
        lastHash = snap.contentHash

        store.insert(ActivityObservation(
            id: UUID().uuidString,
            capturedAt: clock(),
            activeApp: snap.activeApp,
            activeAppBundleId: snap.bundleId,
            activeWindowTitle: snap.windowTitle,
            text: snap.text,
            contentHash: snap.contentHash,
            captureMethod: "ax",
            excluded: false,
            focused: snap.focused
        ))
        return true
    }

    func pruneNow() {
        let days = settings.int("raw_retention_days", default: 14)
        pruner.prune(retentionDays: days, now: clock())
    }
}
