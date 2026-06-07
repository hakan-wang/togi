# Behaviour memory + custom events — design

Date: 2026-06-07
Status: Superseded by `2026-06-07-tailored-data-model-design.md` (folded in; `user_events` is
redefined there in the cat/sub/title/desc shape and built concurrently with the category model).
Scope: macOS app (`apps/macos/Bogi`) — sidecar agent + Swift app + local SQLite. No backend changes.

## Goal

Give the on-device agent two new persistent surfaces it can write to, plus the read
tools to recall them:

1. **Behaviour memory** — a single evolving free-text profile of what the agent has learned
   about how the user works, e.g. _"Håkan often loses focus when working for more than ~35
   minutes, especially during video editing."_ The agent writes this when it notices durable
   patterns and reads it back to inform judging and answers.
2. **Custom events** — a lightweight personal calendar of real-world commitments the user
   mentions in chat (a meeting, a gym session, an appointment). The agent records them on
   demand. Stored separately from `planned_blocks`.

The agent already queries SQLite via read tools (`search_activity`, `summarize_range`,
`list_days`, `list_goals`). This adds **write** capability for behaviour + events and the
**read** tools to recall both.

## Decisions (settled)

- **Events storage:** a new, separate `user_events` table (NOT a reuse of `planned_blocks`).
  Consequence accepted: the judge and summaries must be explicitly taught to read it.
- **Behaviour recall:** a tool the agent calls (`read_behaviour`), not auto-injected into
  context. Recall reliability is mitigated by persona instructions that tell the agent to
  call it before judging/answering.
- **Behaviour storage:** a single evolving document, full-text REPLACE on write
  (`write_behaviour(text)`). Clobber across concurrent judge+chat is not a concern because
  dispatches are serialized in the sidecar (`main.ts` `pending` promise chain — one agent
  runs at a time).
- **UI scope:** v1 is **data + agent only**. Agent-created events are NOT rendered in the
  existing calendar view (which reads `planned_blocks`). Rendering is a fast follow, out of
  scope here.

## Architecture

The write path is fixed by the existing design: the **sidecar opens SQLite read-only**, so
every write flows `agent tool → callAction → stdout action_call frame → SidecarActionHandlers
(Swift) → app's writable GRDB DB`. Both new writes follow that exact pattern, mirroring
`record_segments`. Reads are direct read-only SQL inside sidecar read tools.

```
read_behaviour  ─ readTools.ts ─→ SELECT settings WHERE key='behaviour_profile'   (read-only)
list_events     ─ readTools.ts ─→ SELECT user_events WHERE start_at in [start,end] (read-only)
write_behaviour ─ actionTools ──→ callAction ─→ SidecarActionHandlers ─→ settings UPSERT
add_event       ─ actionTools ──→ callAction ─→ SidecarActionHandlers ─→ user_events INSERT
```

## Components

### 1. Storage — GRDB migration `v5` (`SchemaMigrator.swift`)

New table:

```
user_events
  id          TEXT     PRIMARY KEY
  title       TEXT     NOT NULL
  start_at    DATETIME NOT NULL
  end_at      DATETIME NOT NULL
  category    TEXT                  -- nullable; same closed-set spirit as segments
  notes       TEXT                  -- nullable; one-line elaboration
  created_at  DATETIME NOT NULL
  INDEX (start_at)
```

Behaviour profile reuses the existing `settings(key, value)` table — a single row keyed
`behaviour_profile`. No new table. The sidecar's read-only connection already sees `settings`.

### 2. Swift model + repository

- `UserEvent`: a GRDB `Codable, FetchableRecord, PersistableRecord, TableRecord` record with
  snake_case `CodingKeys`, mirroring `ActivitySegment.swift`.
- `UserEventRepository` (mirrors `PlannedBlockRepository` style):
  - `insert(_ event: UserEvent)`
  - `events(inRange start: Date, _ end: Date) -> [UserEvent]`
  - `events(overlapping date: Date) -> [UserEvent]` (start <= date < end) for the judge.

### 3. Sidecar tools

**`readTools.ts`** (direct read-only SQL):
- `read_behaviour()` → `{ behaviour: string | null }`
  `SELECT value FROM settings WHERE key = 'behaviour_profile'`.
- `list_events(start, end)` → `{ events: [...] }`
  `SELECT id, title, start_at, end_at, category, notes FROM user_events WHERE start_at >= ? AND start_at <= ? ORDER BY start_at`.
  Reuses the existing `normalizeBound` date handling.
- `summarize_range` extended: also fetch `user_events` in range and include them as an
  `events: [...]` array in the returned JSON (teaches the summary to see events).

**`actionTools.ts`** (via `callAction`):
- `write_behaviour({ text })` → `callAction("write_behaviour", { text })`.
  Schema: `{ text: z.string() }`. Description states it REPLACES the whole profile.
- `add_event({ title, start, end, category?, notes? })` → `callAction("add_event", {...})`.
  Schema: title/start/end required strings; category/notes nullish. Description tells the
  agent to resolve relative times against the current time.

All four register automatically via `makeReadTools` / `makeActionTools` in `main.ts` — no
change to the tool wiring there.

### 4. Swift action handlers (`SidecarActionHandlers.swift`)

Add two closures + cases, alongside `createBlock`/`recordSegments`:

- `WriteBehaviour = (_ text: String) async -> Void` → case `"write_behaviour"`: validate
  `text`, upsert `settings['behaviour_profile']`, return `{ ok: true }`.
- `AddEvent = (_ title, _ start: Date, _ end: Date, _ category: String?, _ notes: String?) async -> String?`
  → case `"add_event"`: parse fields (ISO dates via existing `date(_:)`), insert a
  `UserEvent`, return `{ ok: true, id }` or `{ ok: false, error }`.

Wire both in `AppDelegate` (~line 321) using `appState.settings` and a new
`UserEventRepository`, following the existing closure-injection style.

### 5. Judge wiring (`JudgeCoordinator` / `JudgePrompt`)

- `JudgeCoordinator.tick()` fetches `events(overlapping: now)` and passes them into the input.
- `JudgeInput` gains `activeEvents: [(title: String, category: String?, startAt: Date, endAt: Date)]`.
- `JudgePrompt.userJSON` serializes them under `active_events` (array; omitted/empty when none).
- Rationale: the judge sees off-screen commitments (a gym session) and contextualizes
  away-from-keyboard time instead of treating it as off-task. Note: a tick still returns early
  when there are no observations, so events are context, not a trigger.

### 6. Persona (`persona.ts`)

Append guidance (concise, no em-dashes, consistent with existing voice):
- **Recall:** before judging a batch of activity or answering questions about the user's
  habits, call `read_behaviour` to recall what you have learned about them; let it inform
  segmentation and nudges.
- **Learn:** when you notice a durable pattern in how the user works (focus span, recurring
  distractions, what derails them, preferences), call `read_behaviour` to get the current
  profile, then call `write_behaviour` with the full updated text. It REPLACES the whole
  profile, so keep prior insights you still believe. Keep it a short bulleted profile.
- **Events:** when the user mentions a real commitment (a meeting, a gym session, an
  appointment, a call), call `add_event` to record it. Resolve relative times against the
  current time.

## Error handling

- Malformed tool input → handler returns `{ ok: false, error: "bad_input" }` (existing
  convention); the agent sees it as a tool result and can retry or move on.
- `write_behaviour` with empty/missing text → `bad_input`, profile unchanged.
- Read tools open and close their own connection per call (existing pattern); a fresh read
  after a write sees the committed value (WAL).

## Testing

- `SchemaMigrationTests`: `user_events` table + index exist after migration.
- `SidecarActionHandlerTests`: `write_behaviour` and `add_event` parse valid input, dispatch
  to the injected closures, and reject bad input.
- Sidecar vitest (read tools): `read_behaviour` returns the stored value / null; `list_events`
  filters by range; `summarize_range` includes the `events` array.
- Sidecar vitest (action tools): `write_behaviour` / `add_event` schemas + callAction routing.
- `JudgePromptTests`: `active_events` serialization (present, empty, multiple).

## Out of scope (flagged)

- Rendering `user_events` in the calendar UI (v1 is data + agent only).
- Backend changes (none needed).
- Migrating or reconciling `user_events` with `planned_blocks` (the two calendars stay
  independent by design).
- Behaviour history/versioning (single doc, by decision).
```
