# Bogi Full Product Design

Date: 2026-06-05
Status: Approved direction, pending user review of written spec

## Summary

Bogi is a native macOS planning and reality-tracking app. The Mac app is the product center: it owns calendar intent, local reality logs, local context capture, local privacy controls, and the canonical local database. The backend supports sync, account features, Google Calendar OAuth, payments, long-term pattern generation, and AI tool orchestration, but it does not receive continuous raw screen data.

Core product principle:

```text
Calendar = intention.
Reality log = truth.
Data bank = long-term context.
AI coach = better future planning.
```

## Goals

- Build a native Swift macOS app, not Electron.
- Keep raw user context local-first.
- Make calendar planning and reality logging fast enough to use daily.
- Support voice commands and text commands.
- Learn user patterns from planned blocks, reality logs, summaries, and local observations.
- Use AI through structured Bogi-owned tools, not unrestricted computer control.
- Ship outside the Mac App Store first with Developer ID signing, notarization, DMG distribution, and later Sparkle updates.
- Include the full feature surface: local database, EventKit, Google Calendar later, voice, accessibility context, lock-in mode, OCR fallback, backend, Postgres data bank, OpenAI agent layer, payments, observability, export, and delete flows.

## Non-Goals

- No Electron app.
- No always-uploaded raw screen stream.
- No wake word in the first production design.
- No fine-tuning as an initial strategy.
- No social feed.
- No team or corporate dashboard.
- No automatic blocking as a core first behavior.
- No unrestricted AI computer-control layer.

## Product Modes

### Default Mode

Default mode is the daily planning and reality-log experience.

- User creates, edits, and reviews planned calendar blocks.
- User logs reality manually through command bar, mini assistant, voice, or calendar block review.
- Bogi may read local accessibility context whenever permission is granted and the feature is enabled.
- Bogi may use screenshot/OCR fallback for explicit user actions or active sessions when Screen Recording permission is granted.
- Bogi stores raw observations locally.
- Bogi uploads only summaries, user-approved logs, calendar metadata, sync state, and tool results.

### Lock-In Mode

Lock-in mode is an intentional focus session.

- User starts a lock-in session from a planned block, command, menu bar item, or assistant.
- Bogi can use richer local context during the session.
- Accessibility-tree context is preferred.
- Screenshot capture and OCR are fallback mechanisms when accessibility text is insufficient.
- The UI clearly indicates that lock-in monitoring is active.
- Session output is a local session record, reality log, and optional summary.

### Review Mode

Review mode turns data into planning guidance.

- Daily review summarizes planned versus actual work.
- Weekly review identifies patterns, reliable block lengths, recurring distractions, and better future plans.
- AI suggestions must be grounded in stored logs, summaries, calendar blocks, and user patterns.

## macOS App Architecture

### Stack

```text
Language: Swift
UI: SwiftUI
Mac-specific UI: AppKit
Package manager: Swift Package Manager
Minimum target: macOS 14+
Local DB: SQLite via GRDB.swift
Search: SQLite FTS5
Secrets: macOS Keychain
Optional DB encryption: SQLCipher
```

### App Surfaces

- Menu bar item via `NSStatusItem`.
- Mini assistant via `NSPopover` or floating `NSPanel`.
- Command bar via floating `NSPanel`.
- Settings window via SwiftUI.
- Calendar/planning views via SwiftUI.
- Lock-in session panel via SwiftUI plus AppKit window behavior.
- Global hotkey via KeyboardShortcuts.

### Core Services

- `CalendarService`: EventKit integration, local planned blocks, calendar permission state.
- `CommandService`: parses text commands and routes local or AI-backed actions.
- `VoiceService`: push-to-talk recording via AVAudioEngine and transcription API calls.
- `ContextService`: active app/window metadata, accessibility tree reads, local observation diffs.
- `ScreenContextService`: optional ScreenCaptureKit and Vision OCR fallback.
- `DatabaseService`: GRDB migrations, query APIs, FTS search.
- `SyncService`: sync queue, retry, conflict handling, backend API calls.
- `AgentClient`: structured AI calls and Bogi tool execution.
- `PrivacyService`: permission state, user-facing capture state, export/delete controls.
- `SettingsService`: persisted user preferences and feature flags.

## Local Data Model

SQLite is canonical for the Mac app. Backend sync does not replace the local database.

Primary tables:

- `planned_blocks`
- `reality_logs`
- `activity_observations`
- `lock_in_sessions`
- `daily_summaries`
- `weekly_summaries`
- `user_patterns`
- `goals`
- `settings`
- `sync_queue`
- `calendar_accounts`
- `transcripts`
- `agent_runs`

### Planned Blocks

Planned blocks represent intention. A block can map to an Apple Calendar event, a Google Calendar event, or a local-only block.

Required fields:

- id
- source
- external_event_id
- title
- start_at
- end_at
- category
- goal_id
- status
- created_by_bogi
- updated_at

Rules:

- Bogi may update Bogi-created calendar blocks.
- Bogi must not silently delete user-created events.
- External calendar changes are reconciled into local state.

### Reality Logs

Reality logs represent what actually happened.

Required fields:

- id
- block_id
- start_at
- end_at
- category
- user_text
- generated_summary
- confidence
- source
- updated_at

Sources:

- manual text
- voice transcript
- lock-in session summary
- local activity observation summary
- AI-assisted review

### Activity Observations

Activity observations are local raw or semi-raw context records.

Required fields:

- id
- block_id
- captured_at
- active_app
- active_window_title
- local_text_summary
- category_guess
- confidence
- capture_method

Rules:

- Raw accessibility text, screenshot pixels, and OCR text remain local by default.
- The backend receives summaries only when sync settings allow it.
- Observation retention is configurable.

## Context and Privacy Design

The selected product stance is that accessibility and screen context are available for local use after permission is granted. Available does not mean continuously uploaded, and it does not mean silent raw screenshot storage. This is powerful but high-trust, so Bogi must make capture state explicit.

### Permissions

Required:

- Calendar access.
- Microphone access for voice input.

Optional:

- Accessibility access for local text context.
- Screen Recording for screenshot/OCR fallback.

### Context Pipeline

```text
active app/window metadata
→ accessibility tree text
→ local cleanup
→ diff against last state
→ local category classification
→ local observation storage
→ per-block and per-day summaries
→ optional sync of summaries only
```

### Screenshot and OCR Fallback

ScreenCaptureKit and Vision OCR are used only when:

- the user granted Screen Recording permission;
- accessibility context is insufficient;
- lock-in mode, review mode, or an explicit context-assisted command is active;
- the UI indicates that richer context capture is being used.

### Privacy Guarantees

Bogi must communicate these guarantees in settings and onboarding:

- Bogi does not upload raw screenshots by default.
- Bogi does not upload continuous raw screen data.
- Accessibility and OCR context are processed locally first.
- User reality logs are private data-bank records.
- The user can export data.
- The user can delete local and cloud data.

## Voice Design

MVP voice is push-to-talk.

Pipeline:

```text
push-to-talk
→ AVAudioEngine records audio
→ OpenAI speech-to-text
→ transcript stored locally
→ command parser or reality-log parser
→ local action or agent-backed action
```

Initial transcription models:

- `gpt-4o-transcribe`
- `gpt-4o-mini-transcribe`

Later:

- realtime transcription for streaming command UX;
- WhisperKit for local/private transcription.

Supported voice intents:

- create planned blocks;
- move planned blocks;
- create reality logs;
- answer review questions;
- start or end lock-in sessions.

## Calendar Design

### Apple Calendar

EventKit is the native MVP calendar integration.

Capabilities:

- read events;
- create Bogi blocks;
- update Bogi-created blocks;
- associate blocks with local goals and categories;
- detect external edits.

### Google Calendar

Google Calendar is added through backend-managed OAuth for public launch.

Backend responsibilities:

- OAuth callback;
- token storage;
- refresh;
- event sync;
- conflict detection;
- minimal scopes.

The Mac app should continue to treat local SQLite as canonical and use sync state to reconcile external calendars.

## Backend Architecture

### Stack

```text
Language: TypeScript
API: Fastify
Validation: Zod
ORM: Drizzle
Database: Postgres
Vector search: pgvector
Auth: Supabase Auth or custom OAuth later
Payments: Stripe Payment Links first, Checkout/Billing later
```

### Backend Responsibilities

- User auth.
- Device registration.
- Google Calendar OAuth.
- Calendar sync.
- Reality-log sync.
- Daily, weekly, and monthly summary sync.
- Pattern generation.
- Stripe webhook handling.
- Subscription or lifetime entitlement state.
- AI agent tool calls.
- Data export.
- Cloud delete account/data.

### Backend Non-Responsibilities

- No continuous raw screen ingestion.
- No raw screenshot analytics.
- No session replay.
- No always-on surveillance pipeline.

### Postgres Data Bank

Cloud data supports multi-device continuity, long-term retrieval, and AI coaching.

Core cloud tables:

- users
- devices
- calendar_connections
- planned_blocks
- reality_logs
- daily_summaries
- weekly_summaries
- user_patterns
- goals
- agent_runs
- embeddings
- entitlements
- audit_events

Security:

- Row-Level Security for user-owned records.
- Encrypted backups.
- EU region if Sweden/EU is the first market.
- Minimal OAuth scopes.
- No sensitive log content in analytics events.

## AI Agent Layer

### Stack

```text
Agent orchestration: OpenAI Agents SDK
LLM calls: OpenAI Responses/Agents
Memory: Postgres summaries + pgvector retrieval
Structured output: JSON schemas
Tools: Bogi-owned tools only
```

### Tool Surface

- `read_calendar`
- `create_calendar_block`
- `update_calendar_block`
- `get_planned_blocks`
- `save_reality_log`
- `get_reality_logs`
- `get_user_patterns`
- `summarize_day`
- `summarize_week`
- `suggest_next_plan`
- `start_lock_in_session`
- `end_lock_in_session`
- `search_local_history`
- `export_user_data`

### Agent Rules

- Agents operate through typed tool calls.
- Structured outputs are validated before use.
- User-facing actions that modify calendars require clear confirmation unless initiated by an explicit command.
- Raw local screen data is not sent to AI by default.
- AI suggestions must cite the stored pattern or summary they are based on.
- No fine-tuning until rules, retrieval, and statistics are exhausted.

## Payments

Initial:

- Stripe Payment Links for lifetime deal or early paid access.

Later:

- Stripe Checkout.
- Stripe Billing.
- Customer Portal.
- Webhook-based subscription state.

Entitlement state lives in the backend and is cached locally for offline tolerance.

## Distribution

Initial distribution is outside the Mac App Store.

- Developer ID signing.
- Apple notarization.
- DMG installer.
- Sparkle auto-update later.

Reasons:

- faster beta shipping;
- easier permission model;
- no App Store review delay;
- better fit for early desktop productivity software.

## Observability

Use observability lightly.

- Crash reporting: Sentry.
- Product analytics: PostHog or simple custom backend events.
- Backend logs: structured logs.
- No session replay.
- No screen recording analytics.

Allowed product events:

- `created_block`
- `completed_reality_log`
- `missed_reality_log`
- `started_lock_in`
- `ended_lock_in`
- `viewed_week_summary`
- `paid_lifetime`

Analytics must not include reality-log content, transcript content, raw OCR text, raw accessibility text, or screenshots.

## Feature Map

### Planning

- create blocks from command bar;
- create blocks from voice;
- move blocks;
- edit Bogi-created calendar blocks;
- view day/week plan;
- attach goals/categories;
- suggest next plan from patterns.

### Reality Logging

- manual log entry;
- voice log entry;
- planned-versus-actual review;
- lock-in session output;
- local context-assisted summaries;
- daily and weekly summaries.

### Context

- active app/window metadata;
- accessibility tree text;
- local observation diffs;
- local categorization;
- lock-in session monitoring;
- screenshot/OCR fallback.

### AI Coach

- answer “what did I actually do?” questions;
- summarize day/week;
- identify reliable block lengths;
- identify repeated distractions;
- suggest realistic future plans;
- operate through Bogi-owned tools.

### Privacy and Control

- settings for permissions and capture behavior;
- visible capture state;
- export local/cloud data;
- delete account/data;
- retention settings for observations;
- local-first raw context storage.

## Build Phases

The product spec covers all features, but implementation must be phased by dependency order.

### Phase 1: Native Shell and Local Data

- SwiftUI/AppKit project.
- Menu bar item.
- Command bar.
- Settings.
- GRDB SQLite schema and migrations.
- Keychain storage.
- Basic local planned blocks and reality logs.

### Phase 2: Calendar and Daily Loop

- EventKit permissions.
- Apple Calendar read/create/update.
- Day/week planning views.
- Manual reality logs.
- Daily review.

### Phase 3: Voice and Command Parsing

- Push-to-talk.
- AVAudioEngine capture.
- Speech-to-text API integration.
- Voice command intents.
- Transcript storage.

### Phase 4: Local Context

- Active app/window detection.
- Accessibility permission flow.
- AXUIElement reads.
- Local observation storage.
- Diffing and local classification.
- Per-block summaries.

### Phase 5: Lock-In Mode

- Start/end lock-in sessions.
- Visible capture state.
- Session observation aggregation.
- ScreenCaptureKit fallback.
- Vision OCR fallback.
- Session summary and reality-log generation.

### Phase 6: Backend and Sync

- Fastify API.
- Zod validation.
- Drizzle schema.
- Postgres and pgvector.
- Auth.
- Device registration.
- Sync queue protocol.
- Summary and pattern sync.

### Phase 7: AI Agent Layer

- OpenAI Agents/Responses integration.
- Typed tools.
- Structured outputs.
- Retrieval over summaries and patterns.
- Planning suggestions.
- Review Q&A.

### Phase 8: Google Calendar, Payments, Distribution

- Google Calendar OAuth.
- Stripe Payment Links.
- Entitlement cache.
- Developer ID signing.
- Notarization.
- DMG.
- Sparkle updater later.

## Open Decisions

- Whether local SQLite should be encrypted by default or only offered as an advanced setting.
- Whether Supabase Auth or custom OAuth is better for the first public backend.
- Whether local categorization should begin rule-based or use a small local model later.
- How long raw local observations should be retained by default.
- Whether backend AI summaries should be opt-in for privacy-sensitive users.

## Acceptance Criteria

The full product is correctly designed when:

- the Mac app can function offline for core planning and reality logging;
- raw context is local-first;
- the backend has no dependency on continuous raw screen upload;
- calendar intent and reality truth are represented as separate but linkable records;
- voice, text, and UI actions use the same command/action layer;
- AI can only act through typed Bogi-owned tools;
- user data can be exported and deleted;
- payment state can be enforced without breaking offline local history;
- distribution can happen outside the Mac App Store.
