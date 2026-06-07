# Mascot Intro Swoop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After onboarding finishes, fly the floating mascot from screen-center to its bottom-right resting spot and show a one-time, dismissable speech bubble that explains what it is and that it's still learning.

**Architecture:** Reuse the existing `MascotPanel` / `MascotView` / `MascotViewModel` / `SpeechBubble` stack. Add an `introActive` flag to the view model (drives the bubble's dismiss `×` and guards the auto-dismiss timer), an optional `onDismiss` to `SpeechBubble`, a `presentWithIntro()` method on `MascotPanel` that animates the window origin, and a `firstRun` flag threaded through `AppDelegate.startMainExperience` so the swoop only fires on the post-onboarding launch.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit (`NSPanel`, `NSAnimationContext`), XCTest, SwiftPM (`swift build` / `swift test`).

**Working directory for all commands:** `apps/macos/Bogi`

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `Sources/BogiApp/Features/Mascot/MascotState.swift` | Observable mascot state | Add `introActive` published flag + `dismissIntro()` |
| `Tests/BogiAppTests/MascotViewModelTests.swift` | Unit tests for the view model | Create |
| `Sources/BogiApp/Features/Mascot/MascotView.swift` | Mascot rendering + bubble | `SpeechBubble` gains optional `onDismiss` → `×`; call site wires intro; tap clears intro |
| `Sources/BogiApp/Features/Mascot/MascotPanel.swift` | Floating window shell | Add `presentWithIntro()`, `showIntroBubble()`, `introCopy`; extract resting-origin math |
| `Sources/BogiApp/AppDelegate.swift` | App lifecycle wiring | `startMainExperience(firstRun:)`; onboarding passes `true`; call `presentWithIntro()` vs `show()` |

---

## Task 1: View-model intro state (`introActive` + `dismissIntro`)

**Files:**
- Modify: `Sources/BogiApp/Features/Mascot/MascotState.swift`
- Test: `Tests/BogiAppTests/MascotViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/BogiAppTests/MascotViewModelTests.swift`:

```swift
import XCTest
@testable import BogiApp

/// The intro bubble is a one-time, dismissable callout shown right after onboarding. `introActive`
/// tells the view to render a dismiss `×` and guards the auto-dismiss timer; `dismissIntro()` tears
/// the whole thing down. Nudges must never set `introActive`, so nudge bubbles stay button-less.
@MainActor
final class MascotViewModelTests: XCTestCase {
    func testDismissIntroClearsBubbleAndFlag() {
        let vm = MascotViewModel()
        vm.introActive = true
        vm.bubbleText = "Click me anytime."
        vm.escalationLevel = 0
        vm.mood = .speaking

        vm.dismissIntro()

        XCTAssertFalse(vm.introActive, "dismissIntro clears the intro flag")
        XCTAssertNil(vm.bubbleText, "dismissIntro drops the bubble text")
        XCTAssertEqual(vm.escalationLevel, 0, "dismissIntro resets escalation")
    }

    func testNudgeDoesNotActivateIntro() {
        let vm = MascotViewModel()
        let decision = NudgeDecision(show: true, escalationLevel: 1, playSound: false,
                                     text: "you drifted off the deck.")

        vm.apply(decision)

        XCTAssertEqual(vm.bubbleText, "you drifted off the deck.", "a nudge still shows its bubble")
        XCTAssertFalse(vm.introActive, "a nudge must never turn the intro on (no dismiss × on nudges)")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MascotViewModelTests`
Expected: FAIL — compile error, `value of type 'MascotViewModel' has no member 'introActive'` / `'dismissIntro'`.

- [ ] **Step 3: Add `introActive` and `dismissIntro()`**

In `MascotState.swift`, inside `MascotViewModel`, add the published flag next to the other `@Published` properties (after `voiceActive` on line 52):

```swift
    /// True only while the one-time post-onboarding intro bubble is showing. Drives the dismiss
    /// `×` in `SpeechBubble` and guards the auto-dismiss timer in `MascotPanel`. Nudges never set
    /// this, so ordinary nudge bubbles stay button-less.
    @Published var introActive: Bool = false
```

Then add `dismissIntro()` right after `clearBubble(fallback:)` (after line 80):

```swift
    /// End the one-time intro: clear the flag and drop the bubble back to a resting state.
    func dismissIntro() {
        introActive = false
        clearBubble()
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MascotViewModelTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/BogiApp/Features/Mascot/MascotState.swift Tests/BogiAppTests/MascotViewModelTests.swift
git commit -m "feat(mascot): add intro state + dismissIntro to the view model"
```

---

## Task 2: Dismiss `×` on `SpeechBubble` + intro wiring in `MascotView`

This is SwiftUI/AppKit view code on a non-activating panel, so it's verified by build + manual run rather than unit tests. The `×` is built as a tap-gesture overlay (not a `Button`) because the mascot lives in a `.nonactivatingPanel`, where the existing tap interactions are all gesture-based — a `Button` may not receive the first click on a window that never becomes key.

**Files:**
- Modify: `Sources/BogiApp/Features/Mascot/MascotView.swift`

- [ ] **Step 1: Add an optional `onDismiss` and the `×` overlay to `SpeechBubble`**

Replace the entire `SpeechBubble` struct (currently lines 234-257) with:

```swift
/// Small non-modal callout above the mascot. Supportive, not naggy. Copy comes from the caller.
/// When `onDismiss` is supplied (the one-time intro), it shows a quiet `×` to dismiss; nudges pass
/// nil and stay button-less.
private struct SpeechBubble: View {
    let text: String
    let escalationLevel: Int
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        Text(text)
            .font(escalationLevel >= 2 ? .callout.bold() : .caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(BogiColor.ink)
            // Take the full multi-line height so the nudge wraps instead of truncating to
            // one clipped line ("Hey, you j…") inside the panel.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 200)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(escalationLevel >= 2 ? Color.red.opacity(0.6) : Color.white.opacity(0.7), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if let onDismiss {
                    // A tap gesture, not a Button: the mascot panel is non-activating, so the
                    // window never becomes key and a Button can swallow the first click. The
                    // existing mascot tap is gesture-based for the same reason.
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(BogiColor.muted)
                        .background(Circle().fill(.regularMaterial))
                        .contentShape(Circle())
                        .onTapGesture { onDismiss() }
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("Dismiss")
                }
            }
            .shadow(color: Color(hex: 0x285078).opacity(0.25), radius: 8, y: 4)
    }
}
```

- [ ] **Step 2: Wire the intro into the bubble call site**

In `MascotView.body`, replace the bubble block (currently lines 39-42):

```swift
                if !viewModel.voiceActive, let text = viewModel.bubbleText {
                    SpeechBubble(text: text, escalationLevel: viewModel.escalationLevel)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
```

with:

```swift
                if !viewModel.voiceActive, let text = viewModel.bubbleText {
                    SpeechBubble(
                        text: text,
                        escalationLevel: viewModel.escalationLevel,
                        onDismiss: viewModel.introActive ? { viewModel.dismissIntro() } : nil
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
```

- [ ] **Step 3: Clear the intro when the mascot itself is clicked**

In the `dragOrTap` gesture's `.onEnded` closure, the click branch currently reads (lines 106-112):

```swift
            .onEnded { _ in
                let wasClick = !didDrag
                dragStartMouse = nil
                dragStartOrigin = nil
                didDrag = false
                if wasClick { onActivate?() }
            }
```

Replace the `if wasClick { onActivate?() }` line with:

```swift
                if wasClick {
                    // Opening chat ends the intro moment, so retire its bubble alongside.
                    if viewModel.introActive { viewModel.dismissIntro() }
                    onActivate?()
                }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/BogiApp/Features/Mascot/MascotView.swift
git commit -m "feat(mascot): dismiss × on the speech bubble, cleared on click"
```

---

## Task 3: `presentWithIntro()` swoop on `MascotPanel`

**Files:**
- Modify: `Sources/BogiApp/Features/Mascot/MascotPanel.swift`

- [ ] **Step 1: Extract the resting-origin math so `show()` and the swoop share it**

In `MascotPanel.swift`, replace the current `show()` method (lines 54-64):

```swift
    func show() {
        // Bottom-right of the main screen as a default resting spot — only on the
        // first reveal. Subsequent shows (e.g. after hide, or a nudge auto-reappear)
        // keep the position the user last dragged the mascot to.
        if !hasSetInitialPosition, let screen = NSScreen.main {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: frame.maxX - 264, y: frame.minY + 72))
            hasSetInitialPosition = true
        }
        orderFrontRegardless()
    }
```

with:

```swift
    func show() {
        // Bottom-right of the main screen as a default resting spot — only on the
        // first reveal. Subsequent shows (e.g. after hide, or a nudge auto-reappear)
        // keep the position the user last dragged the mascot to.
        if !hasSetInitialPosition, let resting = Self.restingOrigin() {
            setFrameOrigin(resting)
            hasSetInitialPosition = true
        }
        orderFrontRegardless()
    }

    /// Default resting spot: bottom-right of the main screen's visible frame. `nil` when there's
    /// no main screen, so callers can fall back to a plain reveal.
    private static func restingOrigin() -> NSPoint? {
        guard let screen = NSScreen.main else { return nil }
        let frame = screen.visibleFrame
        return NSPoint(x: frame.maxX - 264, y: frame.minY + 72)
    }
```

- [ ] **Step 2: Add the intro copy constant and the swoop**

Still in `MascotPanel.swift`, add the following directly after the new `restingOrigin()` method:

```swift
    /// One-time copy shown the first time the mascot appears, right after onboarding.
    private static let introCopy =
        "Click me anytime to open up — ask me anything. I'm always learning, so I won't know much about you yet."

    /// First reveal after onboarding: place the mascot where the onboarding card was (screen
    /// centre), fly it to its bottom-right resting spot, then drop in the intro bubble. Falls back
    /// to a plain `show()` if there's no main screen, and skips the flight under Reduce Motion.
    func presentWithIntro() {
        guard let resting = Self.restingOrigin(), let screen = NSScreen.main else {
            show()
            showIntroBubble()
            return
        }
        // Mark placed so a later show() won't re-snap the mascot away from where it ends up.
        hasSetInitialPosition = true

        let visible = screen.visibleFrame
        let size = frame.size
        let start = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        setFrameOrigin(start)
        orderFrontRegardless()

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setFrameOrigin(resting)
            showIntroBubble()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.6
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrameOrigin(resting)
        }, completionHandler: { [weak self] in
            self?.showIntroBubble()
        })
    }

    /// Show the intro bubble and auto-dismiss it after ~6s — but only if the user hasn't already
    /// dismissed it (via the × or by clicking the mascot), which `introActive` tells us.
    private func showIntroBubble() {
        viewModel.mood = .idle
        viewModel.escalationLevel = 0
        viewModel.bubbleText = Self.introCopy
        viewModel.introActive = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.viewModel.introActive else { return }
            self.viewModel.dismissIntro()
        }
    }
```

`CAMediaTimingFunction` comes from QuartzCore; AppKit re-exports it, so the existing `import AppKit` at the top of the file is sufficient — no new import needed.

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/BogiApp/Features/Mascot/MascotPanel.swift
git commit -m "feat(mascot): presentWithIntro swoop + auto-dismissing intro bubble"
```

---

## Task 4: Fire the intro only on the post-onboarding launch

**Files:**
- Modify: `Sources/BogiApp/AppDelegate.swift`

- [ ] **Step 1: Thread `firstRun` through `startMainExperience`**

In `AppDelegate.swift`, change the onboarding completion call (line 324) from:

```swift
            presentOnboarding { [weak self] in self?.startMainExperience() }
```

to:

```swift
            presentOnboarding { [weak self] in self?.startMainExperience(firstRun: true) }
```

- [ ] **Step 2: Accept the flag and use it to pick the reveal**

Change the `startMainExperience()` signature (line 353) from:

```swift
    private func startMainExperience() {
```

to:

```swift
    private func startMainExperience(firstRun: Bool = false) {
```

Then, in the same method, change the mascot reveal (line 369) from:

```swift
        if appState.mascotVisible { mascot.show() }
```

to:

```swift
        if appState.mascotVisible {
            // First launch after onboarding gets the one-time swoop + intro bubble; every later
            // launch just reveals the mascot at its last spot.
            if firstRun { mascot.presentWithIntro() } else { mascot.show() }
        }
```

(The already-onboarded path at line 327, `startMainExperience()`, now uses the `firstRun: false` default — unchanged behavior.)

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/BogiApp/AppDelegate.swift
git commit -m "feat(mascot): play the intro swoop only on the post-onboarding launch"
```

---

## Task 5: Full verification

- [ ] **Step 1: Run the unit tests**

Run: `swift test --filter MascotViewModelTests`
Expected: PASS (2 tests).

- [ ] **Step 2: Build the whole package**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Manual behavioral checklist (packaged/run app)**

Build and run the app (per `Packaging/build-app.sh` or the normal run flow), then verify:

1. Reset onboarding (so first-run fires): clear the `onboarding_completed` setting / use a fresh profile. Complete onboarding → the card closes → the mascot **flies from screen-center to bottom-right** → the bubble drops in above it reading *"Click me anytime to open up — ask me anything. I'm always learning, so I won't know much about you yet."* with a `×`.
2. Click the `×` → the bubble disappears; the mascot stays in the corner.
3. Re-trigger first run, this time **click the mascot** → chat (companion) opens **and** the bubble clears.
4. Re-trigger first run, then **wait ~6s** → the bubble auto-fades; the mascot stays.
5. **Quit and relaunch** while already onboarded → the mascot just appears bottom-right, **no swoop, no bubble**.
6. Turn on **System Settings → Accessibility → Display → Reduce Motion**, re-trigger first run → the mascot **does not fly** (appears directly at the corner); the bubble still shows.
7. Toggle the mascot **hidden** (`mascotVisible == false`) before first run → **nothing appears** (no swoop, no bubble); revealing it later uses the plain `show()`.

- [ ] **Step 4: Final commit (if any checklist fixes were needed)**

```bash
git add -A
git commit -m "fix(mascot): address intro swoop verification findings"
```

(Skip if the checklist passed clean with no changes.)

---

## Self-Review Notes

- **Spec coverage:** first-run gating (Task 4), swoop center→corner with Reduce-Motion fallback (Task 3), reuse of `SpeechBubble` with `×` (Task 2), three dismiss paths — `×` (Task 2), mascot click (Task 2 Step 3), 6s auto-fade (Task 3) — and the `introActive`/`dismissIntro` view-model state (Task 1). Edge cases (no `NSScreen.main`, `mascotVisible == false`, double-fire timer guard) are covered in Tasks 3–5.
- **Type/name consistency:** `introActive` and `dismissIntro()` (Task 1) are referenced identically in Tasks 2 and 3. `restingOrigin()`, `presentWithIntro()`, `showIntroBubble()`, `introCopy` are all defined and used within Task 3. `startMainExperience(firstRun:)` defined and called consistently in Task 4. `NudgeDecision(show:escalationLevel:playSound:text:)` matches the real initializer.
- **No placeholders:** every code step shows complete code; manual steps are the only non-code verification and are explicit.
