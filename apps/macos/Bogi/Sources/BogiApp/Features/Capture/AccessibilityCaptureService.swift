import Foundation

#if canImport(AppKit)
import AppKit
import ApplicationServices
#endif

/// A single accessibility read, decoupled from AppKit so the capture decision is
/// unit-testable. The service fills this in from `NSWorkspace` + the AX tree;
/// tests construct it by hand.
struct CapturedSurface: Equatable {
    var activeApp: String?
    var activeAppBundleId: String?
    var windowTitle: String?
    /// Best-effort active web domain (browsers only); nil otherwise.
    var domain: String?
    var rawText: String
}

/// The outcome of evaluating one captured surface against the excludes + diff.
/// (Not `Equatable`: `ActivityObservation` is a shared record type that doesn't
/// conform to `Equatable`, and adding that conformance from this module could
/// collide with a sibling module doing the same. Use the helpers below instead.)
enum CaptureDecision {
    /// Sensitive surface — record only an excluded marker (no text/title).
    case excluded(ActivityObservation)
    /// Identical to the last persisted snapshot — skip.
    case unchanged
    /// No usable text after cleaning — skip.
    case empty
    /// New content to persist.
    case capture(ActivityObservation)

    var isUnchanged: Bool { if case .unchanged = self { return true } else { return false } }
    var isEmpty: Bool { if case .empty = self { return true } else { return false } }

    /// The row to persist for `.capture`/`.excluded`; nil for skip cases.
    var observation: ActivityObservation? {
        switch self {
        case .capture(let o), .excluded(let o): return o
        case .unchanged, .empty: return nil
        }
    }
}

/// Phase 1 capture engine. Every 6 seconds (while not paused and not in DND, and
/// only once Accessibility is granted) it reads the focused element + window text
/// via `AXUIElement` and the frontmost app via `NSWorkspace`, cleans/truncates
/// the text, hashes it, diffs against the last snapshot and persists a new
/// `ActivityObservation` only when something changed. Sensitive surfaces are
/// recorded as excluded markers carrying no verbatim text.
///
/// The pure decision logic lives in `decide(...)`; the AX/`NSWorkspace` reads are
/// thin I/O wrappers around it.
final class AccessibilityCaptureService {
    /// Fixed 6s poll (Goldfish parity, per spec).
    static let defaultInterval: TimeInterval = 6

    /// macOS deep link to the Accessibility privacy pane.
    static let accessibilitySettingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    private let store: ObservationStore
    private let settings: SettingsStore
    private let excludes: CaptureExcludes
    private let processor: CaptureTextProcessor
    private let interval: TimeInterval
    private let now: () -> Date
    private let idProvider: () -> String

    /// Last persisted content/marker hash, used to diff the next read.
    private var lastPersistedHash: String?
    private var timer: Timer?
    private var permissionPollTimer: Timer?

    init(
        store: ObservationStore,
        settings: SettingsStore,
        excludes: CaptureExcludes = CaptureExcludes(),
        processor: CaptureTextProcessor = CaptureTextProcessor(),
        interval: TimeInterval = AccessibilityCaptureService.defaultInterval,
        now: @escaping () -> Date = Date.init,
        idProvider: @escaping () -> String = { UUID().uuidString }
    ) {
        self.store = store
        self.settings = settings
        self.excludes = excludes
        self.processor = processor
        self.interval = interval
        self.now = now
        self.idProvider = idProvider
    }

    // MARK: - Pure decision core

    /// Evaluates a surface against the excludes and the diff. Pure: no AX, no
    /// clock, no I/O — `now`, `id` and `previousHash` are injected.
    func decide(
        surface: CapturedSurface,
        previousHash: String?,
        now: Date,
        id: String
    ) -> CaptureDecision {
        let isExcluded = excludes.isExcluded(
            appBundleId: surface.activeAppBundleId,
            windowTitle: surface.windowTitle,
            domain: surface.domain
        )

        if isExcluded {
            // Never store verbatim text or the (possibly sensitive) title for an
            // excluded surface; dedup consecutive markers by bundle id so a long
            // session in e.g. a password manager produces one marker, not many.
            let marker = processor.hash("excluded:\(surface.activeAppBundleId ?? surface.activeApp ?? "?")")
            guard processor.shouldPersist(newHash: marker, previousHash: previousHash) else {
                return .unchanged
            }
            let observation = ActivityObservation(
                id: id,
                capturedAt: now,
                activeApp: surface.activeApp,
                activeAppBundleId: surface.activeAppBundleId,
                activeWindowTitle: nil,
                text: nil,
                contentHash: marker,
                captureMethod: .ax,
                excluded: true
            )
            return .excluded(observation)
        }

        guard let processed = processor.process(surface.rawText) else {
            return .empty
        }
        guard processor.shouldPersist(newHash: processed.hash, previousHash: previousHash) else {
            return .unchanged
        }
        let observation = ActivityObservation(
            id: id,
            capturedAt: now,
            activeApp: surface.activeApp,
            activeAppBundleId: surface.activeAppBundleId,
            activeWindowTitle: surface.windowTitle,
            text: processed.text,
            contentHash: processed.hash,
            captureMethod: .ax,
            excluded: false
        )
        return .capture(observation)
    }

    /// Applies a decision: persists when there is something to store, and updates
    /// the in-memory diff baseline. Returns the persisted row (if any).
    @discardableResult
    func apply(_ decision: CaptureDecision) throws -> ActivityObservation? {
        switch decision {
        case .unchanged, .empty:
            return nil
        case .excluded(let observation), .capture(let observation):
            let saved = try store.insert(observation)
            lastPersistedHash = observation.contentHash
            return saved
        }
    }

    // MARK: - Lifecycle

    /// Whether capture is currently allowed to write: not paused and not in DND.
    var isActive: Bool {
        !settings.isPaused && !settings.bool(.dnd)
    }

    /// Primes the diff baseline from the most recently persisted row so a restart
    /// doesn't re-store an unchanged snapshot.
    func primeBaseline() {
        lastPersistedHash = (try? store.fetchLatest())?.contentHash
    }

    /// Starts the 6s poll. No-op if Accessibility isn't trusted (call
    /// `requestPermission`/`pollForPermission` first) or if already running.
    func start() {
        guard timer == nil else { return }
        guard isTrusted else { return }
        primeBaseline()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One poll cycle: respect pause/DND, read the surface, decide, persist.
    func tick() {
        guard isActive, isTrusted else { return }
        guard let surface = readSurface() else { return }
        let decision = decide(
            surface: surface,
            previousHash: lastPersistedHash,
            now: now(),
            id: idProvider()
        )
        do {
            try apply(decision)
        } catch {
            NSLog("Bogi capture: failed to persist observation: \(error)")
        }
    }

    deinit {
        timer?.invalidate()
        permissionPollTimer?.invalidate()
    }

    // MARK: - Accessibility permission

    /// `AXIsProcessTrusted()` — true once the user has granted Accessibility.
    var isTrusted: Bool {
        #if canImport(AppKit)
        return AXIsProcessTrusted()
        #else
        return false
        #endif
    }

    /// Triggers the system Accessibility prompt (adds Bogi to the list, prompting
    /// the user). Returns the current trust state.
    @discardableResult
    func requestPermission() -> Bool {
        #if canImport(AppKit)
        // Use the documented key string literal directly. The
        // `kAXTrustedCheckOptionPrompt` constant is imported differently across
        // SDK versions (`CFString` vs `Unmanaged<CFString>`); its value is the
        // stable string "AXTrustedCheckOptionPrompt".
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
        #else
        return false
        #endif
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    func openAccessibilitySettings() {
        #if canImport(AppKit)
        if let url = URL(string: Self.accessibilitySettingsURLString) {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// Polls trust state until granted or `timeout` elapses, then calls back on
    /// the main thread. Used by onboarding after deep-linking to System Settings.
    func pollForPermission(
        every pollInterval: TimeInterval = 1,
        timeout: TimeInterval = 120,
        onResult: @escaping (Bool) -> Void
    ) {
        permissionPollTimer?.invalidate()
        let deadline = now().addingTimeInterval(timeout)
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.isTrusted {
                t.invalidate()
                self.permissionPollTimer = nil
                onResult(true)
            } else if self.now() >= deadline {
                t.invalidate()
                self.permissionPollTimer = nil
                onResult(false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    // MARK: - AX / NSWorkspace I/O

    /// Reads the current frontmost app + focused window text. Returns nil when
    /// nothing usable is available (e.g. no frontmost app).
    func readSurface() -> CapturedSurface? {
        #if canImport(AppKit)
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        let focusedWindow = Self.axElement(appElement, attribute: kAXFocusedWindowAttribute)
        let windowTitle = focusedWindow.flatMap {
            Self.axString($0, attribute: kAXTitleAttribute)
        }

        // Prefer the focused UI element's text; fall back to the window subtree.
        var text = ""
        if let focusedElement = Self.axElement(appElement, attribute: kAXFocusedUIElementAttribute) {
            text = Self.collectText(from: focusedElement, maxNodes: 400)
        }
        if text.isEmpty, let window = focusedWindow {
            text = Self.collectText(from: window, maxNodes: 800)
        }

        return CapturedSurface(
            activeApp: app.localizedName,
            activeAppBundleId: app.bundleIdentifier,
            windowTitle: windowTitle,
            domain: Self.domain(fromWindowTitle: windowTitle),
            rawText: text
        )
        #else
        return nil
        #endif
    }

    #if canImport(AppKit)
    /// Reads a child AXUIElement attribute (e.g. focused window / element).
    private static func axElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Reads a string attribute (e.g. title / value).
    private static func axString(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    /// Depth-first walk collecting `AXValue`/`AXTitle` strings from the subtree,
    /// bounded by `maxNodes` to keep each 6s read cheap.
    private static func collectText(from root: AXUIElement, maxNodes: Int) -> String {
        var pieces: [String] = []
        var visited = 0
        var stack: [AXUIElement] = [root]

        while let element = stack.popLast(), visited < maxNodes {
            visited += 1

            if let value = axString(element, attribute: kAXValueAttribute) {
                pieces.append(value)
            }
            if let title = axString(element, attribute: kAXTitleAttribute) {
                pieces.append(title)
            }

            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                stack.append(contentsOf: children)
            }
        }

        return pieces.joined(separator: "\n")
    }
    #endif

    /// Best-effort domain extraction from a browser window title. Many browsers
    /// surface the page host in the AX title; we only pull an explicit host token
    /// so this is conservative (no false domains for non-browser titles).
    static func domain(fromWindowTitle title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        // Look for a URL-like token inside the title.
        for token in title.split(whereSeparator: { $0 == " " || $0 == "—" || $0 == "-" || $0 == "|" }) {
            let candidate = String(token)
            if candidate.contains("://") || candidate.contains(".") {
                if let normalized = CaptureExcludes.normalizeDomain(candidate),
                   normalized.contains(".") {
                    return normalized
                }
            }
        }
        return nil
    }
}
