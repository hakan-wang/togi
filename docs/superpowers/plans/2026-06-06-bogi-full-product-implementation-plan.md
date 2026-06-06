# Bogi Full Product Implementation Plan

Date: 2026-06-06
Status: Ready to build
Spec: `docs/superpowers/specs/2026-06-06-bogi-datalayer-design.md`
Scope: v1 = the entire spec (no phasing of features; phases below are build order only)

## Build philosophy

- **Greenfield** Swift/SwiftUI macOS app in this worktree. Copy only GRDB + `AXUIElement`
  patterns from `erik-agent-macos`.
- **Local-first**: SQLite (GRDB) is the only user-data store. Backend is a stateless AWS proxy.
- **Vertical slices**: each phase ends with something runnable + tested, not a horizontal layer.
- **Cost-bounded AI**: cheap local capture; one Bedrock call per 5-min judge; on-demand coach.
- Phases are **build order**. All features are v1; this is the sequence to get there safely.

## Project structure

```text
apps/
  macos/Bogi/
    Package.swift
    Sources/BogiApp/
      BogiApp.swift, AppDelegate.swift
      Infrastructure/
        Database/        DatabaseService, SchemaMigrator, models
        Embeddings/      EmbeddingService (CoreML), VectorIndex (sqlite-vec)
        AI/              InferenceClient (→ backend proxy), JudgeService, CoachService
        Auth/            SupabaseAuth, AccountGate (paid status)
        Calendar/        EventKitService, GoogleCalendarService (PKCE)
        Privacy/         PermissionState, CaptureExcludes
        Updates/         Sparkle
      Features/
        Capture/         AccessibilityCaptureService, ObservationStore, RetentionPruner
        Judge/           Judge heartbeat (5-min timer), prompt, parsing
        Planner/         PlannerService, command/voice parsing, calendar reconcile
        Coach/           CoachChat, nudge policy
        Mascot/          MascotPanel (floating NSPanel), MascotState, NudgePresenter
        Voice/           VoiceService (push-to-talk + transcription)
        DataBank/        Day/Week/Month/Year views, insights
      UI/                MenuBarController, SettingsView, PlannerView, BankViews, CoachView
backend/                 (TypeScript, AWS Lambda)
      src/handlers/      infer.ts, stripeWebhook.ts, accountStatus.ts
```

## Dependencies (SPM)

```swift
.package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
.package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.2.0"),
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
.package(url: "https://github.com/jkrukowski/SQLiteVec.git", from: "0.0.13"),
.package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
.package(url: "https://github.com/google/GoogleSignIn-iOS", from: "8.0.0"), // or raw ASWebAuthenticationSession PKCE
```

- **EmbeddingGemma-300M**: bundle a CoreML conversion (or ship `NLContextualEmbedding` fallback
  first, swap in EmbeddingGemma once the CoreML model is validated).
- **Google Calendar**: prefer raw `ASWebAuthenticationSession` + PKCE to avoid SDK weight; tokens
  to Keychain.

---

## Phase 0 — Scaffold + DB foundation

Goal: app launches, menu bar item, settings window, empty SQLite migrated.

- Create `Package.swift` (deps above, macOS 14, executable `Bogi`).
- `BogiApp` + `AppDelegate` (LSUIElement-style menu-bar app, no dock window required).
- `MenuBarController` (`NSStatusItem`) with: open dashboard, pause capture, settings, quit.
- `DatabaseService` (GRDB `DatabaseQueue`) + `SchemaMigrator` — full schema below.
- `SettingsView` shell (tabs: Permissions, Capture, Account, Calendars, About).
- Tests: migration creates all tables; in-memory DB boots.

## Phase 1 — Capture layer (reality)

Goal: AX text captured every 6s, diffed, stored locally; sensitive surfaces excluded; pause works.

- `AccessibilityCaptureService`:
  - `AXIsProcessTrusted()` gate; request-permission flow with primer.
  - 6s repeating timer (suspended when paused / DND).
  - Read focused element + window text via `AXUIElement`; active app via `NSWorkspace`.
  - Clean + truncate text; compute a content hash; **diff** vs last snapshot, skip if unchanged.
- `CaptureExcludes`: bundle defaults (1Password/known password mgrs by bundle id; banking domains;
  private/incognito windows; auth dialogs). User add/remove app + domain.
- `ObservationStore`: insert `activity_observations` rows.
- `RetentionPruner`: daily job deletes raw observations older than `raw_retention_days` (default 14).
- Tests: diff dedup; exclusion match; pruning boundary.

## Phase 2 — Embeddings + search

Goal: durable text is embeddable + searchable, fully on-device.

- `EmbeddingService`: protocol; impl A = `NLContextualEmbedding`; impl B = EmbeddingGemma CoreML
  (256-dim Matryoshka). Feature-flag to switch.
- `VectorIndex`: `sqlite-vec` `vec0` virtual table for segment/summary embeddings; KNN query.
- FTS5 virtual tables over `activity_segments.description` + summaries.
- `SearchService`: hybrid (FTS5 + vector), used by coach + bank browse.
- Tests: round-trip embed→store→KNN; FTS match.

## Phase 3 — Backend (AWS) + auth + paywall

Goal: app logs in (paid only), and can make authorized inference calls through the proxy.

- **Backend (Lambda + API Gateway, TypeScript):**
  - `POST /v1/infer` — verify Supabase JWT → check paid status → forward to **Bedrock Converse
    API** using the **`eu.anthropic.claude-sonnet-4-6` inference profile** (the raw model ID is
    rejected for on-demand) → return completion. Stateless; logs nothing.
  - `POST /v1/stripe/webhook` — on `checkout.session.completed` / subscription events, mark the
    Supabase user `paid=true` (via Supabase admin API or a `profiles` row).
  - `GET /v1/account/status` — returns paid/plan for the authed user.
- **App auth (`SupabaseAuth` + `AccountGate`):**
  - Login screen (email/password or magic link via Supabase).
  - On launch: require session; call `/v1/account/status`; **if not paid → blocking screen with
    "Manage subscription on the website" (opens Stripe-hosted page).**
  - Cache paid status; re-check on launch + periodically.
- Tests (backend): JWT reject; unpaid reject on `/v1/infer`; webhook flips paid flag.

## Phase 4 — Planner + calendars (intent)

Goal: user plans blocks by text/voice; Apple + Google calendars feed/receive blocks.

- `EventKitService`: request access; read events; create/update **Bogi-created** blocks; detect
  external edits; never delete user events.
- `GoogleCalendarService`: `ASWebAuthenticationSession` PKCE → tokens to **Keychain** → direct
  Google Calendar API calls + local refresh. No backend involvement.
- `PlannerService`: maps external events + local blocks into `planned_blocks`; reconciles edits;
  SQLite canonical.
- **"Hey Bogi" command parsing**: text/voice → `/v1/infer` to parse intent → create/move blocks
  ("one hour to edit videos tomorrow"). `VoiceService` = push-to-talk (AVAudioEngine) +
  transcription via `/v1/infer` (or a transcription endpoint).
- `PlannerView`: day timeline of planned blocks; create/edit; calendar account management in
  Settings.
- Tests: block CRUD; reconcile external edit; PKCE token store/refresh (mocked).

## Phase 5 — The 5-minute judge (heartbeat)

Goal: every 5 min, raw observations become categorized reality + nudge decision.

- `JudgeService`: 5-min repeating timer (skips when paused/no activity).
  - Gather last-5-min `activity_observations` + the currently-active `planned_block`.
  - One `/v1/infer` call with the **judge prompt** (below).
  - Parse JSON → write `activity_segments` (category → sub → sub-sub, minutes, on_task,
    `planned_block_id`, confidence) → embed descriptions → if `nudge.should`, hand to
    `NudgePresenter`.
- Cheap aggregation jobs roll segments into `daily/weekly/monthly` summaries.
- Tests: prompt builder shape; JSON parse + segment write; on-task vs off-task classification on
  fixtures; nudge debounce/snooze respected.

## Phase 6 — Mascot + nudges

Goal: floating Bogi that reflects state, nudges calmly→escalating, talkable.

- `MascotPanel`: borderless, always-on-top, non-activating `NSPanel`; draggable; click-through
  where idle. SwiftUI fish view; mood from `MascotState` (on-task / off-task / idle / speaking).
- `NudgePresenter`: non-modal speech bubble; **escalation** if ignored (size + sound after N
  ignored ticks); **snooze** + **per-block DND**. Never a blocking wall.
- Click or "Hey Bogi" (hotkey/voice) → opens coach chat anchored to the mascot.
- Tests: state→mood mapping; escalation timing; snooze suppresses; DND windows.

## Phase 7 — Coach + data bank views

Goal: blunt coach Q&A grounded in the bank; day/week/month/year insights.

- `CoachService`: builds context (active plan, today's segments, relevant retrieval) → `/v1/infer`
  with a **blunt accountability persona** system prompt; answers "where did my week go?", "did I
  hit my goal, why not?", "where do I leak time?".
- `BankViews`: Day (plan vs reality per block), Week/Month/Year (category breakdowns, time
  totals, goal vs outcome, recurring failure patterns).
- `GoalsService`: monthly/longer goals; coach references them.
- Tests: context builder; insight aggregation correctness on fixtures.

## Phase 8 — Packaging + distribution

- Developer ID signing + hardened runtime + **notarization**; entitlements for Accessibility,
  Calendars, Microphone, network.
- DMG build; **Sparkle** appcast + EdDSA signing.
- First-run onboarding: privacy promise → login (paid) → just-in-time Accessibility primer →
  mascot appears.

---

## SQLite schema (GRDB migration `create_core_tables` v2)

Extends the existing tables; adds the judged-segment, nudge, summary, taxonomy, account, and
calendar tables.

```text
planned_blocks      id, source(apple|google|local), external_event_id, title,
                    start_at, end_at, category, goal_id, status, created_by_bogi, updated_at

activity_observations   id, captured_at, active_app, active_app_bundle_id,
                        active_window_title, text, content_hash, capture_method(ax),
                        excluded(bool)          -- raw 6s captures; pruned after retention

activity_segments   id, start_at, end_at, minutes, planned_block_id(FK setNull),
                    category, sub_category, sub_sub(description),
                    on_task(bool), confidence, judged_at        -- the categorized reality
segment_fts         FTS5(description)            -- keyword search
segment_vec         vec0(embedding float[256])  -- semantic search (sqlite-vec)

nudges              id, segment_id(FK), planned_block_id(FK), severity(int),
                    message, shown_at, outcome(dismissed|snoozed|heeded|escalated)

daily_summaries     date, json(category totals, plan-vs-reality), generated_at
weekly_summaries    iso_week, json, generated_at
monthly_summaries   month, json, generated_at

goals               id, title, period(month|quarter|year|custom), target, created_at
categories          id, parent_id(nullable), name      -- evolving taxonomy

calendar_accounts   id, provider(apple|google), display_name, status, last_sync_at
                    -- google tokens live in Keychain, NOT here

settings            key, value          -- raw_retention_days(14), paused, dnd, embed_impl, ...
account             supabase_user_id, paid(bool), plan, checked_at   -- cached gate
```

## The 5-minute judge prompt (concrete)

**System:**
> You are Bogi's activity judge. You receive ~5 minutes of a user's on-screen activity
> (accessibility-captured text snippets, with apps and timestamps) and the calendar block they
> planned for this time. Do three things and return STRICT JSON only:
> 1. Segment the activity into one or more time segments, each labeled
>    `category → sub_category → sub_sub` (sub_sub is a short concrete description) with
>    `minutes`.
> 2. Judge `on_task`: does the dominant activity match the planned block's intent?
> 3. Decide a nudge: only if the user is *sustainedly* off-task vs the plan. Be blunt and
>    specific, never preachy, never a wall. If on-task or no plan, `should=false`.

**User (templated):**
```json
{
  "now": "<iso>",
  "active_block": { "title": "Edit videos", "category": "work/content",
                    "start_at": "...", "end_at": "..." },
  "recent_off_task_minutes": 4,
  "observations": [
    {"t":"...","app":"Safari","window":"LinkedIn Feed","text":"<cleaned snippet>"},
    {"t":"...","app":"Final Cut Pro","window":"Timeline","text":"<snippet>"}
  ]
}
```

**Expected output:**
```json
{
  "segments": [
    {"start_at":"...","end_at":"...","minutes":4,"category":"distraction",
     "sub_category":"social media","sub_sub":"scrolling LinkedIn feed","on_task":false,"confidence":0.9},
    {"start_at":"...","end_at":"...","minutes":1,"category":"work","sub_category":"video editing",
     "sub_sub":"Final Cut timeline","on_task":true,"confidence":0.8}
  ],
  "nudge": {"should": true, "severity": 1,
            "message": "You blocked this hour to edit videos — that's 4 minutes on LinkedIn. Back to the timeline?"}
}
```

## Permission & OAuth flows

- **Accessibility**: `AXIsProcessTrusted()`; if false, primer screen → open System Settings deep
  link; poll for grant; show capture indicator once granted.
- **EventKit / Microphone**: standard `requestAccess` with in-context primers.
- **Google Calendar (PKCE)**: generate verifier/challenge → `ASWebAuthenticationSession` →
  exchange code for tokens (no client secret) → store access+refresh in **Keychain** → refresh
  locally on 401/expiry.

## Backend API (AWS Lambda, all behind Supabase JWT)

```text
POST /v1/infer          { model, messages, max_tokens } → Bedrock Converse (Sonnet 4.6).
                        Verifies JWT, checks paid; forwards; stores nothing.
GET  /v1/account/status → { paid, plan }
POST /v1/stripe/webhook → updates Supabase paid flag (signature-verified)
```

## Testing strategy

- **Swift unit tests** per service (capture diff, exclusions, retention, judge parse, nudge
  policy, calendar reconcile, search round-trip).
- **Fixture-driven judge tests**: canned 5-min observation sets → assert categorization +
  on/off-task + nudge decision.
- **Backend tests**: JWT/paid enforcement, Stripe webhook signature + flag flip, Bedrock proxy
  shape (mocked).
- **Manual**: permission flows, mascot escalation, onboarding paywall.

## Open implementation details (decide during build)

- EmbeddingGemma CoreML conversion vs shipping `NLContextualEmbedding` first.
- ~~Lambda vs App Runner for the backend.~~ **Resolved: Lambda** (App Runner unavailable in
  `eu-north-1`).
- "Learn my rhythm": how historical follow-through adjusts planning suggestions (pattern stats,
  no fine-tuning).
- Voice: push-to-talk first; "Hey Bogi" wake word as a later refinement of the same `VoiceService`.
- Confirm Bedrock zero-retention terms for the region before publishing the privacy claim.
```
