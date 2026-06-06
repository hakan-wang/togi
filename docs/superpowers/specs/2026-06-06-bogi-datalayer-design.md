# Bogi Product Design — AI Accountability Coach + Life Data Bank

Date: 2026-06-06
Status: Approved direction (locked via grill), pending written-spec review
Supersedes: the earlier "Bogi data-layer / Goldfish writing-assistant" framing (writing dropped)

## Summary

Bogi is a native macOS **private AI accountability coach** backed by a **longitudinal life
data bank**. It auto-captures what you actually do (via the accessibility tree, every 6s,
stored locally), compares that reality against the intentions you planned into your calendar,
and **shows you the gap** — in the moment, via a floating mascot that nudges you when you drift
off-task, and over time, via categorized day/week/month/year insights.

```text
Calendar planning   = INTENTION  ("edit videos 2h" — concrete, checkable)
Auto-captured reality = REALITY   (what you actually did, logged automatically)
The product         = THE GAP between who you said you'd be and who you were.
The moat            = the data bank — a year of real behavior nobody can fast-follow.
```

### What changed in this grill (important)

- **The Goldfish-style ⌥ "write a reply in your tone" assistant is DROPPED entirely.** That was
  Goldfish's use case, not Bogi's. Bogi borrows Goldfish's *capture tech, privacy model, and
  floating-companion UX* — not its writing product.
- **The PDF's "manual accounting / friction is the product" thesis is REJECTED.** Reality is
  **auto-logged** via AX every 6s, not manually confessed. Bogi watches; it doesn't make you
  type out what you did. What we keep from the PDF: intention/reality/gap, the data bank as the
  moat, the honest/blunt coach, hierarchical categorization, and the day→year zoom.

## Goals

- Native Swift macOS app (not Electron).
- Auto-capture reality locally and continuously; never make the user manually log.
- Supply intent via a lightweight calendar planner ("Hey Bogi").
- Close the intention–reality gap two ways: **in the moment** (floating mascot nudges) and
  **over time** (categorized data-bank insights).
- Keep all captured data **local-first and local-only** — no sync, no cloud storage of user data.
- Keep AI cost bounded: cheap local capture + a periodic 5-minute judge + on-demand coach queries.
- Host 100% of backend infrastructure on AWS (covered by AWS Activate credits).
- Ship outside the Mac App Store: Developer ID, notarization, DMG, Sparkle updates.

## Non-Goals

- No ⌥ write-in-your-tone writing assistant. No tone-matching of the user's voice.
- No screenshots, screen recording, or OCR.
- No continuous per-sample LLM use; no streaming capture to the model.
- No cloud sync, cross-device, or cloud backup (dropped, not "later").
- No MCP / Claude Desktop integration.
- No screen-time-style blocking walls. Mindfulness via honest feedback, not blocking.
- No nagging via "a hundred notifications" (PDF council guardrail).
- No Mac App Store distribution. No free/anonymous tier.

## Locked Decisions

| # | Decision | Resolution |
|---|---|---|
| 0 | Product identity | AI accountability coach + life data bank. Writing assistant dropped. |
| 1 | Intent source | Calendar planned blocks via the "Hey Bogi" planner |
| 1b | Calendar sources | Apple (EventKit permission) + Google (client-side PKCE, tokens in Keychain, direct API). No calendar data on backend |
| 2 | Capture method | Accessibility tree only; no screenshots ever |
| 3 | Cadence | 6s fixed poll, diff before persist |
| 4 | Reality logging | Auto via capture (PDF "manual friction" thesis rejected) |
| 5 | AI heartbeat | 5-min judge: categorize + compare-to-plan + decide/compose nudge |
| 6 | On-demand AI | Coach queries (chat / "ask AI about my life") |
| 7 | Retention | Raw ~14d local (configurable) → pruned; summaries/logs durable |
| 8 | Retrieval | FTS5 + sqlite-vec; on-device EmbeddingGemma-300M |
| 9 | Mascot | Always-floating; calm idle, escalating nudges; "Hey Bogi"; snooze/DND |
| 10 | Categorization | Hierarchical: category → sub → sub-sub (description) |
| 11 | Insights | Day / week / month / year views over the data bank |
| 12 | Inference | AWS Bedrock, Claude Sonnet 4.6 |
| 13 | Infra / sync | Local-only data; AWS backend (proxy + Stripe + Supabase check); no data store |
| 14 | Auth / payments | Supabase (free tier, auth only) / Stripe (website checkout) |
| 15 | Account | Paid-account-first login; pay on website |
| 16 | Codebase | Greenfield macOS target in this worktree; copy DB + AX snippets only |
| 17 | Distribution | Developer ID + notarized DMG + Sparkle (outside Mac App Store) |

## The Core Loop

```text
PLAN (intent)        you plan calendar blocks via "Hey Bogi"
   ↓
CAPTURE (reality)    AX reads visible text every 6s → cleaned → diffed → stored locally
   ↓
JUDGE (every 5 min)  one LLM call over the last ~5 min of activity:
                       1. categorize it (category → sub → sub-sub, time-attributed)
                       2. compare against the active planned block
                       3. if sustained off-task → compose a nudge
   ↓
NUDGE (in the moment) floating mascot surfaces the nudge (calm → escalating)
   ↓
BANK (over time)     5-min segments aggregate into day/week/month/year insights
   ↓
COACH (on demand)    blunt, honest Q&A grounded in the bank ("where did my week go?")
```

## Capture (reality)

### Method — accessibility only

Reads text via macOS Accessibility (`AXUIElement` tree + `NSWorkspace` app/window metadata).
**No screenshots, no screen recording, no OCR** — ever. Blind to text in images / canvas apps /
poorly-accessible apps; that blind spot is accepted. Requires **Accessibility** permission; does
**not** require Screen Recording.

### Cadence — 6s poll with diff

Fixed 6-second poll (Goldfish parity); each read diffed against the last snapshot, only
meaningful deltas persisted.

### Scope and controls

Default: capture-all **except** auto-excluded sensitive surfaces shipped by default — password
managers, banking/finance sites, private/incognito windows, system auth dialogs. Controls:
global **pause**, **exclude app**, **exclude domain**, natural-language **blacklist** via the
coach.

## The 5-Minute Judge (AI heartbeat)

The heartbeat that turns raw capture into product value. Every 5 minutes, one Bedrock (Claude
Sonnet 4.6) call processes the previous ~5 min of raw activity and does three jobs at once:

1. **Categorize** into the reality log — `category → sub-category → sub-sub (description)`, with
   time attribution (how many minutes on what).
2. **Compare** the activity against the currently-active planned block.
3. **Nudge decision** — if there's a *sustained* off-task mismatch, compose a blunt, contextual
   nudge; otherwise stay quiet.

Cost: ~12 small calls/hour during active use (on AWS Activate credits). Hourly/daily/weekly
rollups are cheap aggregations of these 5-min segments. Additional LLM use is **on-demand** for
coach chat / life questions.

## Intent — the planner ("Hey Bogi")

The intent backbone (un-parked from the original Bogi spec). The user plans the day into
calendar blocks by text or voice ("I need one hour to edit videos tomorrow"; "put a meeting at
3"). Concrete, checkable blocks ("edit videos 1h") are the unit the loop reads from.

- Blocks carry category + goal association.
- The planner exists to create the blocks the loop checks against — "useful on its own, but not
  why the app exists."

### Calendar sources

Two integrations, both keeping calendar data local:

- **Apple Calendar — EventKit permission.** Read events, create/update Bogi-created blocks,
  detect external edits. Bogi may update its own blocks; it must not silently delete
  user-created events.
- **Google Calendar — client-side OAuth (installed-app PKCE, no client secret).** Tokens stored
  in the **macOS Keychain**; the Mac app calls the Google Calendar API directly and refreshes
  locally. **No tokens or calendar data ever touch the backend** — preserves the local-first /
  "nothing leaves your Mac" claim. The backend stays purely proxy + billing.

Local SQLite remains canonical for planned blocks; external calendar state is reconciled in.

## Coach + Floating Mascot

### The mascot

Always-floating desktop companion (the Bogi fish). Idle animation/mood reflects on- vs
off-task. Draggable. Click or **"Hey Bogi"** voice to talk. The on-screen presence *is* the
coach's body.

### Nudge policy — calm, escalating, never a wall

- Off-task nudge starts as a **quiet, non-modal speech bubble**.
- **Escalates** (larger, sound) only if ignored mid-drift — enough to break a real doomscroll.
- **Snooze** + **per-block do-not-disturb**.
- Never blocks the screen (not a screen-time wall — explicit PDF guardrail). Tone is **blunt and
  honest**, not a cheerleader ("you blocked this hour for the deck — that's 12 minutes of
  LinkedIn").
- Respects the "don't bury them in notifications" guardrail: nudges fire on sustained mismatch,
  not constantly.

### The coach (on demand)

Blunt accountability persona. Knows your goals and plan, grounded strictly in the bank. Answers
"what did I actually do today / this week?", "did I hit my monthly goal, and if not why?",
"where do I keep leaking time?". The coach speaks *to* you; it does not write *as* you.

## Data Bank + Insights (the moat)

Every 5-min judged segment becomes categorized, time-attributed data. Aggregated and viewable:

- **Day:** what the hours actually contained, plan vs reality per block.
- **Week / Month / Year:** zoom-out; goal vs outcome; where time leaked; "in your control or
  not?" patterns; recurring failure modes ("you keep planning to email manufacturers and keep
  not doing it").
- **Ask-AI-about-your-life:** on-demand coach queries over the bank for recommendations and
  reflection.

The longitudinal behavior database — not the categorization (replicable) or UX (copyable) — is
the moat. 1,000 users × 100 daily judged segments = a compounding asset.

## Memory: retention & retrieval

Local SQLite (GRDB) is the only store of user data.

- **Raw verbatim AX text:** rolling **~14 days** (configurable), then pruned (privacy lever;
  text-only, a few MB/day).
- **Categorized reality logs + summaries + embeddings:** durable — the persistent bank.
- **Search/retrieval (for coach Q&A + bank browse):** **FTS5** (keyword) + **sqlite-vec**
  (semantic, brute-force, ample at personal scale). Embeddings = **on-device EmbeddingGemma-300M**
  (CoreML, 256-dim Matryoshka; fallback Apple `NLContextualEmbedding`). Nothing leaves the device
  for indexing.

## Inference

**AWS Bedrock — Claude Sonnet 4.6**, via the backend proxy (keys never ship in the client).
Used by: the 5-min judge, the coach (on demand), and planner parsing. Confirm Bedrock
zero-retention terms for the deployment region before publishing the privacy claim.

## Infrastructure

- **Data residency:** 100% local on the Mac. No sync, no cross-device, no cloud backup. Only an
  **auth/paid-status check** touches the cloud (Supabase).
- **Backend (AWS, on Activate credits):** Bedrock proxy + Stripe webhooks + Supabase
  paid-status check. **No user-data store.** Recommended compute: Lambda (scales to zero) or
  App Runner.
- **Auth:** Supabase free tier — accounts only, not data. **Payments:** Stripe — checkout on the
  website.
- **Cost:** Bedrock + backend on AWS Activate credits; capture/storage/search/embeddings $0
  (on-device); Supabase free; Stripe per-transaction fee. Nothing falls outside that.

## Account & Onboarding

- **Paid-account-first.** App requires login; only paid accounts can log in. Unpaid → pushed to
  pay on the **website** (Stripe). No free/anonymous/local trial.
- Funnel: website → pay → download → log in.
- Highest-risk in-app step is the **Accessibility permission** grant — asked just-in-time with a
  plain-language privacy primer; capture/mascot shown immediately to build trust. (Goldfish
  reported ~40% onboarding drop.)

## Privacy Guarantees (user-facing)

- Reads text via accessibility only — **no screenshots, no screen recording, ever**.
- Captured data is stored **locally** and **never uploaded or synced**.
- The LLM sees only **bounded slices** — the 5-min judge window and your on-demand coach
  queries — never a background stream of everything.
- Inference on a private AWS Bedrock deployment with zero retention.
- Sensitive surfaces excluded by default; user can pause, exclude any app/domain, set retention,
  and delete the local bank.
- It is **not** a screen-time blocker and does not police you for anyone else — the data is
  yours, for you.

## Build

```text
Language:        Swift
UI:              SwiftUI + AppKit (floating mascot = borderless NSPanel, always-on-top)
Package manager: Swift Package Manager
Minimum target:  macOS 14+
Local DB:        SQLite via GRDB.swift  (+ FTS5)
Vector search:   sqlite-vec (SQLiteVec Swift bindings)
Embeddings:      EmbeddingGemma-300M (CoreML) | fallback NLContextualEmbedding
Calendar:        EventKit (Apple) + Google Calendar API (client-side PKCE, Keychain tokens)
Voice:           AVAudioEngine push-to-talk + transcription ("Hey Bogi")
Inference:       AWS Bedrock — Claude Sonnet 4.6 (via backend proxy)
Hotkey:          KeyboardShortcuts
Secrets:         macOS Keychain
Backend:         AWS (Lambda/App Runner) — proxy + Stripe webhooks + Supabase check
Auth:            Supabase (free tier)
Payments:        Stripe (website checkout)
```

App surfaces: floating **mascot** (central), **menu-bar** item, **planner/calendar** view,
**day/week/month/year** insight views, **coach chat**, **capture indicator**, **settings**
(permissions, retention, excludes, account).

### Codebase strategy — greenfield

Fresh macOS target in this worktree (`erik-data-only`). Copy only the GRDB/SQLite patterns and
`AXUIElement` capture code from `erik-agent-macos`; the parked planner/calendar/voice code there
may be referenced when un-parking intent, but build clean.

### Distribution

Outside the Mac App Store (forced by website/Stripe billing): Developer ID signing,
notarization, DMG, Sparkle updates.

## Scope

**v1 = everything in this spec.** No phasing. Every feature described above — auto-capture, the
5-min judge, the "Hey Bogi" planner with both Apple (EventKit) and Google (PKCE) calendars, the
floating mascot + escalating nudges, the honest coach, the categorized data bank with
day/week/month/year insights, voice ("Hey Bogi"), local-only storage, the AWS backend,
Supabase/Stripe paid-first billing, and DMG distribution — ships in the first release.

## Open (implementation details only — not scope cuts)

- **"Learn my rhythm" behavior** — how future planning adjusts from historical follow-through
  (PDF feature); pattern-derived, no fine-tuning. In scope; mechanism to detail in the plan.
- **Voice depth** — push-to-talk vs always-listening "Hey Bogi" wake word. Voice ships in v1;
  the wake-word vs push-to-talk choice is an implementation detail.
- Exact schema for `planned_blocks`, `reality_logs` (categorized segments),
  `activity_observations`, summaries, and the 5-min judge prompt.
- Backend compute choice (Lambda vs App Runner).
- Confirm Bedrock zero-retention terms before marketing the privacy claim.
