# Mascot intro swoop — design

**Date:** 2026-06-07
**Status:** Approved for planning
**Area:** macOS app (`apps/macos/Bogi`), Mascot feature

## Problem

When onboarding finishes, the frosted setup card disappears and the floating
mascot panel silently snaps into the bottom-right corner with no explanation.
The user is never told what the icon is, that it's clickable, or that the coach
starts out knowing little and learns over time. The first contact with the
persistent UI is a cold, unexplained pop-in.

## Goal

Turn that silent pop-in into a one-time, lightweight intro moment, fired only on
the post-onboarding launch:

1. The mascot appears where the onboarding card just was (screen center) and
   **swoops across** to its bottom-right resting spot.
2. On arrival, a **speech bubble** drops in above it explaining what it is and
   setting the "I'm still learning" expectation.
3. The bubble is dismissable three ways: a small `×`, clicking the mascot
   (which also opens chat), or an automatic fade after ~6 seconds.

Non-goals: no new onboarding step, no persisted "seen intro" flag (onboarding
completion already gates first-run), no changes to nudge bubbles' behavior, no
redesign of the mascot art or resting position.

## Existing pieces this builds on

- `MascotPanel` (`Features/Mascot/MascotPanel.swift`) — borderless floating
  `NSPanel`. `show()` places it bottom-right on first reveal
  (`x: frame.maxX - 264, y: frame.minY + 72`) and preserves the user's dragged
  position thereafter via `hasSetInitialPosition`.
- `MascotView` (`Features/Mascot/MascotView.swift`) — renders the bobbing
  mascot and, above it, a `SpeechBubble` whenever `viewModel.bubbleText != nil`
  and not in a voice exchange. The bubble already animates in with
  `.move(edge: .top).combined(with: .opacity)`.
- `SpeechBubble` (private struct in `MascotView.swift`) — frosted callout, max
  width 200, white stroke at low escalation / red at high. Currently has no
  dismiss affordance.
- `MascotViewModel` (`Features/Mascot/MascotState.swift`) — observable state:
  `mood`, `bubbleText`, `escalationLevel`, `vitality`, voice fields. `clearBubble()`
  already tears a bubble down and resets mood.
- `AppDelegate.startMainExperience()` (`AppDelegate.swift:353`) — creates the
  `MascotPanel`, calls `show()` if `appState.mascotVisible`, and is reached both
  on a normal launch and, via `presentOnboarding { startMainExperience() }`
  (`AppDelegate.swift:324`), right after onboarding.

## Design

### 1. First-run signal into `startMainExperience`

`startMainExperience()` currently can't tell a fresh post-onboarding launch from
a normal one. Add a parameter:

```swift
private func startMainExperience(firstRun: Bool = false)
```

- `startMainExperienceIfNeeded()`: the onboarding path passes `firstRun: true`:
  `presentOnboarding { [weak self] in self?.startMainExperience(firstRun: true) }`.
  The already-onboarded path calls `startMainExperience()` (defaults to `false`).
- In the body, replace the mascot reveal:

  ```swift
  if appState.mascotVisible {
      if firstRun { mascot.presentWithIntro() } else { mascot.show() }
  }
  ```

No new persisted flag — onboarding completion is the single source of truth for
"first run," and the intro only ever rides the post-onboarding completion.

### 2. `MascotPanel.presentWithIntro()`

New method that performs the swoop, then triggers the bubble. It owns *only*
window geometry + timing; the bubble text/`×` state lives in the view model.

```
func presentWithIntro() {
    1. Compute the resting origin (same math as show()'s bottom-right spot) and
       a start origin centered on NSScreen.main.visibleFrame, accounting for the
       220×220 panel size. Mark hasSetInitialPosition = true so a later show()
       won't re-snap.
    2. setFrameOrigin(start); orderFrontRegardless().
    3. If accessibilityReduceMotion is on (NSWorkspace.shared.accessibility-
       DisplayShouldReduceMotion): setFrameOrigin(resting) immediately, then
       showIntroBubble(). Return.
    4. Otherwise animate to resting over ~0.6s:
         NSAnimationContext.runAnimationGroup({ ctx in
             ctx.duration = 0.6
             ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
             animator().setFrameOrigin(resting)
         }, completionHandler: { [weak self] in self?.showIntroBubble() })
}
```

`showIntroBubble()`:
- Sets `viewModel.introActive = true` and
  `viewModel.bubbleText = MascotPanel.introCopy` with `escalationLevel = 0`,
  `mood = .idle` (neutral white-stroke styling).
- Schedules auto-dismiss: `DispatchQueue.main.asyncAfter(deadline: .now() + 6)`
  that clears the bubble **only if the intro is still up**
  (`if self.viewModel.introActive { self.dismissIntro() }`), so a user who
  already dismissed or clicked through isn't disturbed.

`dismissIntro()`:
- `viewModel.introActive = false`; `viewModel.clearBubble()`.

Intro copy (single constant on `MascotPanel`):

> "Click me anytime to open up — ask me anything. I'm always learning, so I
> won't know much about you yet."

`onActivate` (clicking the mascot → opens chat) should also clear the intro:
since the click opens the companion, the intro bubble is no longer wanted. Have
the view's tap path call `dismissIntro()` before/alongside `onActivate?()`, or
have `AppDelegate`'s `onActivate` closure unaffected and instead clear in the
panel — simplest: in `MascotView`'s tap handler, if `viewModel.introActive`,
call a `viewModel`-level dismiss. See §4.

### 3. `MascotViewModel` — intro state

Add:

```swift
@Published var introActive: Bool = false
```

And a small dismiss helper so the view doesn't poke fields directly:

```swift
func dismissIntro() {
    introActive = false
    clearBubble()
}
```

`introActive` exists purely to (a) tell `SpeechBubble` to render the `×` and
(b) guard the auto-dismiss timer. Nudges never set it, so nudge bubbles stay
button-less and unchanged.

### 4. `SpeechBubble` — optional dismiss `×`

Give `SpeechBubble` an optional dismiss closure; render a small `×` only when
it's provided:

```swift
private struct SpeechBubble: View {
    let text: String
    let escalationLevel: Int
    var onDismiss: (() -> Void)? = nil
    // when onDismiss != nil, overlay a small circular × button (top-trailing),
    // tappable, that calls onDismiss(). Styled quiet (muted ink, no heavy chrome)
    // so it reads as "dismiss" not "alert".
}
```

In `MascotView`, the call site becomes:

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

The mascot's existing tap gesture (`dragOrTap` → `onActivate`) should also end
the intro when clicked. Add to the click branch of `.onEnded`: if
`viewModel.introActive`, call `viewModel.dismissIntro()` (then still fire
`onActivate?()` so chat opens as today).

## Data flow

```
onboarding finishes
  → AppDelegate.presentOnboarding completion
  → startMainExperience(firstRun: true)
  → mascot.presentWithIntro()
       → place center, order front
       → animate window origin → bottom-right (or jump, if Reduce Motion)
       → showIntroBubble(): viewModel.introActive = true,
                            viewModel.bubbleText = introCopy
                            schedule 6s auto-dismiss
  → SpeechBubble drops in above mascot, with ×
  → user dismisses via ×  | clicks mascot (opens chat) | 6s timeout
       → viewModel.dismissIntro() → introActive=false, bubble cleared
```

Normal (already-onboarded) launches call `startMainExperience()` →
`mascot.show()` → unchanged behavior.

## Edge cases

- **Reduce Motion:** skip the fly entirely; place at the corner and show the
  bubble. (Bubble's own transition is a short fade/move and is acceptable; if we
  want it fully still we can wrap the bubble set in the existing reduce-motion
  guard, but the drop-in is mild and consistent with nudges.)
- **`mascotVisible == false` at first run:** user has the mascot hidden; we do
  **not** force it visible for the intro. The `if appState.mascotVisible` guard
  stays, so no swoop or bubble — consistent with respecting their choice.
- **No `NSScreen.main`:** fall back to `show()`'s plain reveal (no swoop), then
  the bubble — never crash on a missing screen.
- **User drags the mascot during the swoop:** acceptable; the animation is
  short (~0.6s) and `isMovableByWindowBackground` interactions during a
  programmatic animation are an extreme edge — no special handling.
- **Double-fire safety:** the 6s timer checks `introActive` before clearing, so
  a manual dismiss or click-through can't be undone by a late timer.

## Testing

This is animation/orchestration glue on AppKit window geometry, which is hard to
unit-test meaningfully. Coverage:

- **Unit (`MascotViewModel`):** `dismissIntro()` sets `introActive = false` and
  clears `bubbleText`/`escalationLevel`/resets mood. A nudge `apply(_:)` does
  **not** set `introActive` (nudges stay button-less).
- **Manual / behavioral checklist** (documented in the plan, verified in the
  running app):
  1. Fresh onboarding → card closes → mascot flies center→corner → bubble with
     correct copy appears with a `×`.
  2. `×` dismisses; bubble gone, mascot stays put.
  3. Clicking the mascot opens chat **and** clears the bubble.
  4. Leaving it ~6s auto-fades the bubble.
  5. Quit & relaunch (already onboarded) → mascot just `show()`s bottom-right,
     no swoop, no bubble.
  6. Reduce Motion on → no fly; bubble still shows.
  7. Mascot hidden (`mascotVisible == false`) at first run → nothing appears.

## Files touched

| File | Change |
|---|---|
| `Features/Mascot/MascotPanel.swift` | Add `presentWithIntro()`, `showIntroBubble()`, `dismissIntro()`, `introCopy` constant; share resting-origin math with `show()`. |
| `Features/Mascot/MascotView.swift` | `SpeechBubble` gains optional `onDismiss` → renders `×`; call site wires it for intro; tap handler clears intro on click. |
| `Features/Mascot/MascotState.swift` | `MascotViewModel`: add `introActive`, `dismissIntro()`. |
| `AppDelegate.swift` | `startMainExperience(firstRun:)`; onboarding completion passes `true`; call `presentWithIntro()` vs `show()`. |
```
