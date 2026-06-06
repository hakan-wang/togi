# Hide-Mascot Menu Option — Design

Date: 2026-06-06

## Goal

Add an option in the menu-bar (status-bar) dropdown to hide / show the floating
mascot (Bogi). The preference persists across launches. While hidden, the mascot
auto-reappears to deliver a nudge, then settles back to hidden. Re-showing
restores the mascot's last on-screen position rather than snapping to a corner.

## Background

- The mascot is a borderless, always-on-top `NSPanel` (`MascotPanel`) created and
  shown unconditionally at launch in `AppDelegate.applicationDidFinishLaunching`.
- The menu-bar dropdown is `MenuBarContent`, which already binds a `Toggle` to
  `AppState.capturePaused` — the established pattern to mirror.
- `AppState.capturePaused` is a `@Published` bool whose `didSet` persists to
  `SettingsStore` (`setBool` / `bool`). The panel itself lives in `AppDelegate`,
  not `AppState`, so visibility changes route through a closure, exactly like the
  existing `openDashboard` / `runJudgeNow` wiring.
- The judge heartbeat (`JudgeCoordinator.tick`) pushes a `show: false` decision
  (mood update) every tick first, and only later may a `show: true` nudge arrive
  via `postNudge`. That ordering makes "auto-reappear, then settle back to
  hidden on the next non-nudge tick" clean to implement.

## Approach

Mirror the `capturePaused` pattern: a `@Published var mascotVisible: Bool` on
`AppState`, persisted to `SettingsStore` in its `didSet`, bound to a `Toggle` in
`MenuBarContent`. Visibility changes route to the panel via a closure on
`AppState` that `AppDelegate` wires at launch.

(Alternative considered: a Combine `sink` on `$mascotVisible` in `AppDelegate`.
Rejected — the codebase uses the closure idiom, not Combine subscriptions, for
AppState → AppDelegate wiring.)

## Changes

### `MascotPanel.swift`
- Add `private var hasSetInitialPosition = false`.
- In `show()`, run the default bottom-right `setFrameOrigin(...)` placement only
  the first time (`hasSetInitialPosition`); thereafter `orderFrontRegardless()`
  preserves the last position. → "last position" behavior.
- Add `func hide() { orderOut(nil) }`.

### `AppDelegate.swift` — `AppState`
- Add `@Published var mascotVisible: Bool`, initialized from
  `settings.bool("mascot_visible", default: true)`. Its `didSet`:
  - `settings.setBool("mascot_visible", mascotVisible)`
  - `onMascotVisibilityChanged?(mascotVisible)`
- Add `var onMascotVisibilityChanged: ((Bool) -> Void)?`.

### `AppDelegate.swift` — `AppDelegate`
- At launch: `if appState.mascotVisible { mascot.show() }` (was unconditional).
- Wire `appState.onMascotVisibilityChanged = { [weak self] visible in
  visible ? self?.mascot?.show() : self?.mascot?.hide() }`.
- In `applyNudge`:
  - On `decision.show == true`: call `mascot.show()` first (auto-reappear; no
    reposition), then apply the bubble.
  - On `decision.show == false`: after the mood update, if
    `appState.mascotVisible == false` call `mascot.hide()` (settle back to
    hidden on the next non-nudge tick).

### `MenuBarContent.swift`
- Add `Toggle("Show Mascot", isOn: $appState.mascotVisible)` alongside the
  existing `Pause Capture` toggle.

## Out of scope
- No change to the Settings window (`CompanionSettingsView`); the request is
  specifically about the menu-bar dropdown.
- No change to the judge/capture loop; it keeps running while hidden — only the
  visible/audible nudge surface changes.

## Testing
- `MascotPanel.show()`/`hide()` position preservation is the main unit-testable
  unit; `AppState.mascotVisible` persistence mirrors the existing
  `capturePaused` persistence behavior.
- Build the macOS app to verify compilation and manually confirm: toggle hides
  the mascot, relaunch restores the saved state, a nudge reappears the mascot,
  and re-showing keeps the dragged position.
