# Bogi (macOS app)

Native macOS **private AI accountability coach** backed by a **longitudinal life
data bank**. Bogi auto-captures what you actually do (accessibility tree, every
6s, stored locally), compares it against the intentions you planned into your
calendar, and shows you the gap — in the moment via a floating mascot, and over
time via day/week/month/year insights.

- Spec: [`docs/superpowers/specs/2026-06-06-bogi-datalayer-design.md`](../../../docs/superpowers/specs/2026-06-06-bogi-datalayer-design.md)
- Plan: [`docs/superpowers/plans/2026-06-06-bogi-full-product-implementation-plan.md`](../../../docs/superpowers/plans/2026-06-06-bogi-full-product-implementation-plan.md)

## Build

```bash
cd apps/macos/Bogi
swift build           # requires a macOS toolchain (AppKit/SwiftUI)
swift test
```

> Bogi targets **macOS 14+** and uses AppKit/SwiftUI; it only builds on macOS.

## Architecture (local-first)

SQLite (GRDB) is the **only** store of user data — no cloud sync. The backend is
a stateless AWS proxy (Bedrock inference + Stripe webhook + Supabase paid-status
check) that stores no user data.

```
Sources/BogiApp/
  BogiApp.swift, AppDelegate.swift, AppEnvironment.swift
  Infrastructure/
    Database/   DatabaseService, SchemaMigrator (full v1 schema), Records, SettingsStore
    Embeddings/ EmbeddingService (CoreML), VectorIndex (sqlite-vec vec0)        [Phase 2]
    AI/         InferenceClient (→ backend proxy), JudgeService, CoachService   [Phase 3/5/7]
    Auth/       SupabaseAuth, AccountGate                                       [Phase 3]
    Calendar/   EventKitService, GoogleCalendarService (PKCE)                   [Phase 4]
    Privacy/    PermissionState, CaptureExcludes
  Features/
    Capture/    AccessibilityCaptureService, ObservationStore, RetentionPruner  [Phase 1]
    Judge/      JudgeService heartbeat (5-min)                                   [Phase 5]
    Planner/    PlannerService, command/voice parsing, calendar reconcile        [Phase 4]
    Coach/      CoachChat, nudge policy                                          [Phase 7]
    Mascot/     MascotPanel (floating NSPanel), MascotState, NudgePresenter      [Phase 6]
    Voice/      VoiceService (push-to-talk + transcription)                      [Phase 4]
    DataBank/   Day/Week/Month/Year views, insights                             [Phase 7]
  UI/           MenuBarController, SettingsView, PlannerView, BankViews, CoachView
```

### Foundation contracts

The foundation (this branch) provides the build system, the **full database
schema**, GRDB record models, the `SettingsStore`, the app/menu-bar/settings
skeleton, and the cross-module contracts feature modules build against:

- `InferenceClient` — protocol + request/response types for the backend proxy.
- `PermissionSnapshot` — permission state shared across capture/calendar/voice.
- `Records` — `PlannedBlock`, `ActivityObservation`, `ActivitySegment`, `Nudge`,
  `Goal`, `Category`, `CalendarAccount`, `AccountRecord`, `Setting`.

`segment_vec` (sqlite-vec `vec0`) is created at runtime by `VectorIndex` after
the sqlite-vec extension is loaded, not in the GRDB migrator (which can't create
a `vec0` table without the extension).
