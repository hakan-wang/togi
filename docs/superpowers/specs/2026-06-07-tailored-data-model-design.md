# Tailored data model: categories + behaviour + events — design

Date: 2026-06-07
Status: Approved (pending spec review)
Scope: macOS app (`apps/macos/Bogi`) — sidecar agent + Swift app + local SQLite. No backend changes.
Supersedes: `2026-06-07-behaviour-memory-and-custom-events-design.md` (folded in here, built concurrently).

## Goal

Make every activity record share one fixed field shape, and make everything those fields
*contain* — including the category set itself — tailored data the agent curates. The only
static thing in code is the four-field structure. Categories, their names, and their colors are
data, evolving per user, just like the behaviour profile and the events calendar.

This delivers three agent-tailored surfaces on top of the existing read tools:

1. **Category registry** — the closed-at-any-moment set of categories (id, name, color), seeded
   with 9 defaults but curated by the agent over time.
2. **Behaviour memory** — a single evolving free-text profile of how the user works.
3. **Custom events** — a lightweight personal calendar of real-world commitments the user
   mentions in chat.

## The unified field model

Every activity record carries the same four columns:

| Level | Field | Rules |
|---|---|---|
| 1 | `cat` | references a `category_registry` id, or null = unknown. The only level with a registry + color. |
| 2 | `sub` | free text — project / place / app (e.g. Litro, Gym, TikTok). No id, no color, no list. |
| 3 | `title` | the calendar/list headline. |
| 3 | `desc` | one-line "what it actually was". |

Applied to all three record tables: `activity_segments` (reality), `planned_blocks` (plan),
`user_events` (conversation-sourced commitments).

A block reads: `deepwork → Litro → "Formula v3 doc" / "Finish the write-up."`

## Decisions (settled)

- **Nothing static but the fields.** The category set is DB data, not source. Colors live in
  the registry (DB), so the UI reads category colors from data — none are hardcoded. The 9
  defaults exist only as a one-time migration seed and are referenced nowhere else.
- **Registry owner: the agent, via an explicit tool** (`manage_categories`), mirroring
  `write_behaviour`. Not auto-extended on use, not user-only.
- **Enforcement: reject.** A non-null `cat` on any write must already exist in the registry,
  else the handler returns `bad_input` and the agent retries (curate first). `cat` may be null
  = unknown (e.g. an imported calendar block). `on_task` is unchanged on segments — it is
  plan-adherence, orthogonal to `cat`.
- **Merge rewrites everywhere.** `merge(from → into)` reassigns `cat = into` across all three
  record tables (segments + planned_blocks + user_events), then deletes `from`. The persona/
  tool description states this consequence so the agent merges deliberately.
- **Behaviour storage:** a single evolving document, full-text REPLACE on write. Stored as one
  row in `settings` keyed `behaviour_profile`. Clobber across concurrent judge+chat is a
  non-issue because the sidecar serializes dispatches (`main.ts` `pending` chain).
- **Behaviour recall:** a tool the agent calls (`read_behaviour`), not auto-injected; the
  persona nudges it to call before judging/answering.
- **Events storage:** the new `user_events` table, defined directly in the four-field shape
  (this supersedes the earlier `title/category/notes` shape). Independent from `planned_blocks`.
- **UI scope:** v1 is **data + agent only**. The registry exposes colors via a repository for
  the UI to consume, but agent-created events are not rendered in the calendar, and broad chart
  restyling is a fast follow. No backend changes.

## Architecture

The sidecar opens SQLite **read-only**, so every write flows
`agent tool → callAction → stdout action_call frame → SidecarActionHandlers (Swift) → writable
GRDB DB`, exactly like the existing `record_segments`. Reads are direct read-only SQL in the
sidecar read tools.

```
list_categories  ─ readTools ─→ SELECT category_registry                         (read-only)
read_behaviour   ─ readTools ─→ SELECT settings WHERE key='behaviour_profile'    (read-only)
list_events      ─ readTools ─→ SELECT user_events WHERE start_at in [start,end]  (read-only)
manage_categories─ actionTools→ callAction → handlers → category_registry +/− reassigns cats
write_behaviour  ─ actionTools→ callAction → handlers → settings UPSERT
add_event        ─ actionTools→ callAction → handlers → user_events INSERT
record_segments  ─ actionTools→ callAction → handlers → activity_segments INSERT (cat-validated)
```

## Components

### 1. Storage — GRDB migration `v5_tailored_data_model` (`SchemaMigrator.swift`)

One migration that:

- **Replaces** the unused legacy `categories` table (only ever created, never read/written)
  with a flat registry:

  ```
  category_registry
    id          TEXT     PRIMARY KEY      -- stable slug, e.g. 'deepwork'
    name        TEXT     NOT NULL         -- display name
    color       TEXT     NOT NULL         -- hex, e.g. '#2E5BFF'
    description TEXT                       -- nullable meaning hint for the agent
    sort_order  INTEGER  NOT NULL DEFAULT 0
    created_at  DATETIME NOT NULL
    updated_at  DATETIME NOT NULL
  ```

  Seeded with 9 defaults (editable thereafter):
  deepwork `#2E5BFF`, creative `#8B5CF6`, admin `#64748B`, health `#22C55E`, social `#EC4899`,
  errands `#F59E0B`, leisure `#14B8A6`, scroll `#EF4444`, personal `#9CA3AF`.

- **Renames/extends `activity_segments`**: `sub_category → sub`, `sub_sub → title`,
  `category → cat`; add `desc TEXT`. (SQLite `RENAME COLUMN` + `ADD COLUMN`, or table-recreate
  via GRDB if FTS/refs require it.) Backfill: `desc` stays null; existing free-text `cat` values
  are not in the seed set, so set `cat = NULL` (data volume is tiny; we do not invent mappings).

- **Renames/extends `planned_blocks`**: `category → cat`; add `sub TEXT`, `desc TEXT`. `title`
  already exists. Existing `cat` values set to NULL (same reasoning).

- **Creates `user_events`** in the four-field shape:

  ```
  user_events
    id          TEXT     PRIMARY KEY
    title       TEXT     NOT NULL
    desc        TEXT
    cat         TEXT                       -- registry id or null
    sub         TEXT
    start_at    DATETIME NOT NULL
    end_at      DATETIME NOT NULL
    created_at  DATETIME NOT NULL
    INDEX (start_at)
  ```

- Behaviour profile reuses `settings` (one row keyed `behaviour_profile`). No schema change.

The `segment_fts` virtual table is unchanged; the app keeps feeding it a joined `description`
string (now built from `cat`/`sub`/`title`).

### 2. Swift models + repositories

- `CategoryEntry`: GRDB record for `category_registry` (snake_case CodingKeys).
- `CategoryRepository`:
  - `all() -> [CategoryEntry]` (ordered by `sort_order`)
  - `exists(_ id: String) -> Bool` (write validation)
  - `add` / `rename` / `recolor` / `merge(from:into:)` — `merge` reassigns `cat` in
    `activity_segments`, `planned_blocks`, `user_events` then deletes `from`, in one transaction.
  - `color(for id: String) -> Color?` for the UI.
- `UserEvent`: GRDB record for `user_events`, mirroring `ActivitySegment.swift`.
- `UserEventRepository`: `insert`, `events(inRange:_:)`, `events(overlapping:)` (start ≤ date < end).
- `ActivitySegment` / `PlannedBlock`: renamed properties + CodingKeys (`cat`/`sub`/`title`/`desc`).

### 3. Sidecar read tools (`readTools.ts`, direct read-only SQL)

- `list_categories()` → `{ categories: [{ id, name, color, description }] }` ordered by `sort_order`.
- `read_behaviour()` → `{ behaviour: string | null }` from `settings`.
- `list_events(start, end)` → `{ events: [...] }`, reusing `normalizeBound` + the `datetime()`
  range handling (see the timestamp-format fix already in `readTools.ts`).
- `summarize_range` extended: group by `cat` (was `category`); also fetch `user_events` in range
  and include them as an `events: [...]` array.
- `search_activity` / `list_days`: group/return by `cat`. (Raw-observation fallback unchanged.)

### 4. Sidecar action tools (`actionTools.ts`, via `callAction`)

- `manage_categories({ op, ... })` → `callAction("manage_categories", {...})`. Ops:
  - `add({ name, color?, description? })` — handler derives a stable slug `id` from `name`
    (e.g. "Deep work" → `deepwork`); if `color` is omitted it assigns a default from a small
    palette not already in use.
  - `rename({ id, name })`
  - `recolor({ id, color })`
  - `merge({ from, into })`
  Description states merge reassigns the category across all records then deletes it.
- `write_behaviour({ text })` — REPLACES the whole profile.
- `add_event({ title, desc?, cat?, sub?, start, end })` — resolve relative times against now.

`record_segments` schema changes: `category/sub_category/sub_sub` → `cat/sub/title/desc`
(keeps `minutes`, `on_task`, `confidence`, `start_at`, `end_at`).

All register automatically via `makeReadTools` / `makeActionTools` / `makeRecordTools` in
`main.ts` — no tool-wiring change there.

### 5. Swift action handlers (`SidecarActionHandlers.swift`) + wiring

Add closures + cases alongside `createBlock` / `recordSegments`:

- `case "manage_categories"`: route by `op` to `CategoryRepository`; validate; return `{ ok }`
  (or `{ ok:false, error:"bad_input" }`).
- `case "write_behaviour"`: validate non-empty `text`, upsert `settings['behaviour_profile']`.
- `case "add_event"`: parse fields (ISO dates via existing `date(_:)`), validate `cat` against
  the registry when present, insert a `UserEvent`, return `{ ok:true, id }`.
- `record_segments`: validate each non-null `cat` against the registry; reject the batch with
  `bad_input` if any is unknown.

Wire in `AppDelegate` (~line 321) with `CategoryRepository`, `UserEventRepository`, and
`appState.settings`, following the existing closure-injection style. The `recordSegments` /
FTS description string is rebuilt from `cat`/`sub`/`title`.

### 6. Judge wiring (`JudgeCoordinator` / `JudgePrompt` / `JudgeResult`)

- `JudgeResult.swift` (`JudgeSegment`): renamed fields + CodingKeys.
- `JudgeCoordinator.tick()` fetches `events(overlapping: now)` and passes them in.
- `JudgeInput` gains `activeEvents: [(title, cat:String?, startAt, endAt)]`.
- `JudgePrompt.userJSON` serializes them under `active_events` (omitted/empty when none) and the
  documented output shape uses `cat/sub/title/desc`. A tick still returns early with no
  observations, so events are context, not a trigger.

### 7. Persona (`persona.ts`)

Append (concise, no em-dashes):
- **Categories:** before segmenting or labeling, call `list_categories` to see the current set.
  Use an existing category whenever one fits. Only when nothing fits, call `manage_categories`
  (add/rename/recolor), and use `merge` to combine two categories that are really the same —
  merge reassigns that category across all the user's past activity, plans, and events, then
  removes it, so do it deliberately.
- **Behaviour:** before judging a batch or answering habit questions, call `read_behaviour`.
  When you notice a durable pattern, call `read_behaviour` then `write_behaviour` with the full
  updated profile (REPLACE; keep prior insights you still believe; keep it a short bulleted list).
- **Events:** when the user mentions a real commitment (meeting, gym, appointment, call), call
  `add_event`, resolving relative times against the current time.

### 8. UI colors

Views that color by category read `CategoryRepository.color(for:)`. Broad chart restyling is a
fast follow; v1 only exposes the repository and wires colors where category coloring already
exists.

## Error handling

- Malformed tool input → `{ ok:false, error:"bad_input" }` (existing convention); the agent
  sees the tool result and retries or moves on.
- Unknown `cat` on any write → `bad_input`, nothing persisted.
- `write_behaviour` with empty text → `bad_input`, profile unchanged.
- `merge` with a missing `from`/`into` id → `bad_input`, no reassignment.
- Read tools open/close their own connection per call; a fresh read after a write sees the
  committed value (WAL).

## Testing

- **Migration**: `category_registry` exists with 9 seed rows; `user_events` table + index;
  `activity_segments` / `planned_blocks` have `cat/sub/title/desc`; legacy `categories` gone.
- **CategoryRepository**: add/rename/recolor; `merge` reassigns `cat` across all three tables
  and deletes the source; `exists` gating.
- **SidecarActionHandlers**: `manage_categories` each op; `write_behaviour`; `add_event`;
  `record_segments` rejects an unknown `cat`; bad input rejected.
- **Sidecar vitest (read)**: `list_categories`, `read_behaviour` (value/null), `list_events`
  range filter, `summarize_range` groups by `cat` and includes `events`.
- **Sidecar vitest (action)**: `manage_categories` / `write_behaviour` / `add_event` schemas +
  callAction routing; `record_segments` new schema.
- **JudgePromptTests**: `active_events` serialization (present, empty, multiple); output-shape doc.

## Out of scope (flagged)

- Rendering `user_events` in the calendar UI; broad chart restyle (v1 = data + agent only).
- Backend changes (none needed).
- Reconciling `user_events` with `planned_blocks` (independent by design).
- Behaviour history/versioning (single doc, by decision).
- Hard category delete (use `merge`); auto-extension on use (explicit tool only).
- Inventing mappings from old free-text categories to the seed set (old `cat` → NULL).
