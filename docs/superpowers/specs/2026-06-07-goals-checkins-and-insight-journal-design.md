# Goals, check-ins & the insight journal (Notice + Remember) — design

Date: 2026-06-07
Status: Approved (pending spec review)
Scope: macOS app (`apps/macos/Bogi`) — sidecar agent + Swift app + local SQLite. No backend changes.
Builds on: `2026-06-07-tailored-data-model-design.md` (the `feat/tailored-data-model` branch / migration v5).
This is **migration v6 on top of v5**; it assumes the four-field shape, `category_registry`,
the `settings`-based user memory (`north_star`, `behaviour_profile`), `user_events`, and the
v5 tool set already exist.

## Goal

Port three surfaces from the "Togi Variant B" web prototype into the native macOS app, as one
coherent layer rather than three bolt-ons:

1. **Dashboard** — statistics from the SQLite logs + the agent's every-5-minute judged segments
   (mostly already exists; we surface the new data on it).
2. **Behavioural insights** — the agent derives human-readable patterns ("Håkan often loses focus
   ~35 min into video editing") and surfaces them in the UI.
3. **Goals via chat** — the user tells Togi a goal in chat; the agent persists it, schedules
   check-ins, nudges proactively, documents the journey, and keeps the goal in context.

## Design philosophy (inherited from the tailored data model)

The tailored data model established: **nothing is static but the four fields; everything the
agent curates is data**, read via read-only SQL tools and written via
`callAction → SidecarActionHandlers → GRDB`. The judge heartbeat (`JudgeCoordinator.tick()`,
every 5 min) already feeds observations + active block + active events to the agent, which
segments and nudges in one loop.

This design **adds no new mechanisms**. It adds two kinds of agent-curated data in the same
grain and reuses the loops that already exist.

## The core idea: two kinds of memory

The agent needs both, and they are layers, not competitors:

- **`behaviour_profile` = semantic memory** (from v5). The agent's *current synthesized* model of
  the user. One free-text doc in `settings`, REPLACE-on-write via `write_behaviour`, pulled into
  context. Not dated, not browsable. **Unchanged by this design.**
- **`journal` = episodic memory** (new). *Discrete, dated, evidenced* discoveries and moments:
  "Jun 7 — noticed you lose focus ~35 min into editing." Browsable, dismissible, links to the
  evidence that produced it.

The agent **distills** durable journal entries into `behaviour_profile` (episodic → semantic,
like human memory). The prototype's "Notice + Remember" framing maps directly:
**Notice = `journal`**, **Remember = `behaviour_profile`**.

The key simplification: **a behavioural insight, a goal-progress note, and a check-in outcome are
the same shape** — a dated agent note, optionally scoped to a goal or category, optionally
evidenced. They are **one table**, distinguished by `kind`. One stream powers three views:

- Dashboard **Insights** section = `journal WHERE kind = 'insight'`.
- A goal's **journey** timeline = `journal WHERE goal_id = X`.
- A logged check-in = `journal kind = 'checkin'` tied to a goal.

Check-ins reuse what v5 already wired: a scheduled check-in is a `user_events` row; the judge
tick already fetches overlapping events; the agent decides and nudges; the reply is logged to
`journal`.

## Decisions (settled)

- **Two memory types, not one.** `journal` (episodic, dated, evidenced, UI-facing) is separate
  from `behaviour_profile` (semantic, synthesized, context-facing). The agent writes journal
  entries freely and periodically folds durable ones into `behaviour_profile`.
- **Insights, goal-progress, and check-in outcomes are one `journal` table** keyed by `kind`.
  Scope is an optional `goal_id` and/or `cat`; null scope = a global behavioural insight.
- **Check-ins are `user_events`, not a new scheduler.** `add_event` (v5) gains an optional
  `goal_id`; `cat = 'checkin'` marks it. The existing `events(overlapping:)` fetch in
  `JudgeCoordinator.tick()` is the trigger. No timer, no second agent-invocation path.
- **Check-in firing = "wake the agent, let it decide."** A due check-in is context in the judge
  payload; the agent decides whether to `post_nudge` (and may skip if the user is mid-flow).
- **Granular goals sit between the apex and events.** The apex goal stays `north_star` /
  `north_star_why` (v5 identity, user-owned, read via `read_behaviour`). The `goals` table holds
  granular, trackable objectives; their journey is `journal`, their check-ins are `user_events`.
- **Insight generation is agent-driven, not scheduled.** The agent calls `log_journal` whenever
  it deems necessary — mid-chat, while judging a batch, while reading logs. No cron.
- **Every new tool mirrors a v5 tool** and the same `callAction` write / read-only-SQL read split.
- **`cat` is registry-validated** on every write that carries a non-null `cat` (goals, journal),
  exactly like v5's `record_segments` / `add_event`. Unknown `cat` → `bad_input`.
- **UI is the deferred v5 fast-follow.** v5 shipped data+agent only; the dashboard surfacing here
  (Pillar 1) is that fast-follow. No backend changes anywhere.

## The delta on top of v5

### 1. Storage — GRDB migration `v6_goals_and_journal` (`SchemaMigrator.swift`)

One migration that:

- **Extends `goals`** (keep `id`, `title`, `period`, `target`, `created_at`):
  - add `why TEXT` — the motivation the user gives ("document my journey" needs the *why*).
  - add `status TEXT NOT NULL DEFAULT 'active'` — `active | done | abandoned`.
  - add `cat TEXT` — optional registry id the goal is primarily about (validated on write).
  - add `updated_at DATETIME` (backfilled to `created_at`).

- **Creates `journal`** (episodic memory; the four-field grain in `title`/`desc`):

  ```
  journal
    id          TEXT     PRIMARY KEY
    created_at  DATETIME NOT NULL
    kind        TEXT     NOT NULL         -- insight | progress | checkin | milestone
    goal_id     TEXT     REFERENCES goals(id) ON DELETE SET NULL   -- nullable scope
    cat         TEXT                       -- registry id or null (validated when non-null)
    title       TEXT     NOT NULL         -- headline ("Loses focus ~35 min into editing")
    desc        TEXT                       -- the detail / body
    confidence  DOUBLE                     -- nullable; mostly for kind=insight
    evidence    TEXT                       -- nullable JSON: [{start_at,end_at}] time-ranges
    status      TEXT     NOT NULL DEFAULT 'active'   -- active | dismissed | superseded
    INDEX (created_at), INDEX (goal_id), INDEX (kind)
  ```

  Evidence references **time-ranges**, not segment ids, so it survives retention pruning and
  re-judging.

- **Adds `goal_id TEXT REFERENCES goals(id) ON DELETE SET NULL` to `user_events`** so an event
  (including a `cat='checkin'` event) can attach to a goal. Index unchanged.

No change to `category_registry`, `settings`, `activity_segments`, `planned_blocks`, FTS, or
embeddings.

### 2. Swift models + repositories

- `GoalRecord`: extend with `why`, `status`, `cat`, `updatedAt` (snake_case CodingKeys).
- `GoalsService`: extend with `update(id, status?/target?/why?/cat?)`; keep `add` / `all` /
  `delete`. `all(status:)` filter for active goals.
- `JournalEntry`: new GRDB record for `journal`, mirroring `ActivitySegment` style.
- `JournalRepository`:
  - `insert(_:)`
  - `entries(kind:?, goalId:?, inRange:?, limit:?) -> [JournalEntry]` (newest first)
  - `setStatus(id:, status:)` (dismiss / supersede)
- `UserEvent` / `UserEventRepository` (from v5): add `goalId` to the record + an
  `events(forGoal:)` query; keep `events(overlapping:)`.

### 3. Sidecar read tools (`readTools.ts`, read-only SQL)

- `list_goals` (extend v5): include `why`, `status`, `cat`; default to `status='active'` with an
  optional `includeAll` flag.
- `list_journal({ kind?, goal_id?, start?, end?, limit? })` → `{ entries: [...] }`, newest first.
  Mirrors `list_events`; reuses `normalizeBound` / `datetime()` range handling.
- `summarize_range` (extend): include a small `recentInsights` array (latest `kind='insight'`
  journal entries overlapping the range) so the coach can reference them without a second call.

### 4. Sidecar action tools (`actionTools.ts`, via `callAction`)

- `manage_goal({ op, ... })` — mirrors `manage_categories`. Ops:
  - `add({ title, why?, period?, target?, cat? })` — handler derives a slug `id`, validates `cat`.
  - `update({ id, status?, why?, target?, cat? })`.
  - (delete stays the existing path; not exposed unless needed.)
- `log_journal({ kind, title, desc?, goal_id?, cat?, confidence?, evidence? })` — append one
  journal entry. Validates `kind` and (when present) `cat` and `goal_id`.
- `set_journal_status({ id, status })` — dismiss / supersede an entry (used rarely by the agent;
  the UI uses it directly via the repository).
- `add_event` (extend v5): accept an optional `goal_id`; when `cat='checkin'` + `goal_id` set,
  this *is* a scheduled check-in. No new tool.

`record_segments` and the v5 tools are unchanged. All register via the existing
`makeReadTools` / `makeActionTools` factories — no `main.ts` wiring change.

### 5. Swift action handlers (`SidecarActionHandlers.swift`) + wiring

Add closures + cases alongside v5's `manage_categories` / `add_event`:

- `case "manage_goal"`: route by `op` to `GoalsService`; validate `cat` against the registry;
  return `{ ok }` or `{ ok:false, error:"bad_input" }`.
- `case "log_journal"`: validate `kind`; validate `cat`/`goal_id` when present; insert a
  `JournalEntry`; return `{ ok:true, id }`.
- `case "set_journal_status"`: validate `status`; update; return `{ ok }`.
- `add_event` handler (v5): accept and persist `goal_id`.

Wire in `AppDelegate` alongside the v5 injections, with `GoalsService`, `JournalRepository`, and
the extended `UserEventRepository`, following the existing closure-injection style.

### 6. Context + judge wiring (`JudgeCoordinator` / `JudgePrompt` / `JudgeInput`)

The judge tick already fetches `events(overlapping: now)` and the agent already calls
`read_behaviour`. Extend the payload so proactivity rides the existing loop:

- `JudgeInput` gains `activeGoals: [(id, title, status, cat?)]` and
  `dueCheckIns: [(eventId, goalId, title)]` (events with `cat='checkin'` overlapping now).
- `JudgePrompt.userJSON` serializes them under `active_goals` / `due_check_ins` (omitted when
  empty). A tick still returns early when there are no observations, so goals/check-ins are
  context, not a trigger — except a *due check-in* is itself reason enough to run a tick; the
  coordinator calls `tick()` when `dueCheckIns` is non-empty even if observations are sparse.
- After the agent posts a check-in nudge, the app deletes that check-in event so it does not
  re-fire (the outcome is preserved as a `journal kind='checkin'` entry, so nothing is lost).
  Recurrence is not stored on the goal: a
  repeating check-in is the agent scheduling the *next* `add_event` when it logs the current
  check-in (`log_journal kind='checkin'` + a fresh `add_event`), keeping cadence as data the
  agent curates rather than a fixed column.

### 7. Persona (`persona.ts`)

Append (concise, no em-dashes), continuing the v5 additions:

- **Goals:** when the user states a goal or intention in chat, call `manage_goal add` with the
  title and their *why*. Offer to schedule check-ins; if they agree, call `add_event` with
  `cat='checkin'` and the `goal_id` at the cadence they want. Read active goals before answering
  progress questions.
- **Journal (Notice):** when you notice a durable behavioural pattern while judging a batch or
  reading logs, call `log_journal kind='insight'` with a short headline, a one-line detail, a
  confidence, and the time-ranges that show it. Check recent insights first (via the summarized
  context or `list_journal`) so you do not repeat one. Periodically fold durable insights into
  `write_behaviour` (Remember). Log goal progress as `kind='progress'`.
- **Check-ins:** when a `due_check_in` appears in the payload, decide whether to `post_nudge`
  inviting a quick reflection (skip if the user is clearly mid-flow). When the user replies,
  record it with `log_journal kind='checkin'` tied to the goal.

### 8. UI — the deferred fast-follow (Pillar 1, on the dashboard)

`DashboardView` / `InsightView` gain two read-only sections fed by new stores; no separate goal
screen (per the chosen "journey shown on the dashboard"):

- **Insights** section: `JournalRepository.entries(kind: .insight, status: .active)` rendered as
  cards (title, detail, confidence). A dismiss control calls `setStatus(.dismissed)`.
- **Goals & journey** section: active goals (`GoalsService.all(status: .active)`) with their next
  check-in (`UserEventRepository.events(forGoal:)`) and a recent journey timeline
  (`JournalRepository.entries(goalId:)`).
- Category coloring reads `CategoryRepository.color(for:)` (v5), no hardcoded colors.

## Architecture / data flow

```
list_journal     ─ readTools  ─→ SELECT journal                              (read-only)
list_goals       ─ readTools  ─→ SELECT goals                                (read-only)
manage_goal      ─ actionTools→ callAction → handlers → goals INSERT/UPDATE  (cat-validated)
log_journal      ─ actionTools→ callAction → handlers → journal INSERT       (cat/goal-validated)
add_event(+goal) ─ actionTools→ callAction → handlers → user_events INSERT   (= a check-in)

JudgeCoordinator.tick() every 5 min:
  observations + active block + active_events + active_goals + due_check_ins
    → agent → record_segments / post_nudge / log_journal / write_behaviour
  due check-in present → agent decides → post_nudge → user reply → log_journal(checkin)

Dashboard (read-only): journal (insights + per-goal journey) + goals + registry colors
```

## Error handling

Follows the v5 convention — handlers return `{ ok:false, error:"bad_input" }` and the agent
sees the result and retries or moves on:

- Unknown `cat` on `manage_goal` / `log_journal` → `bad_input`, nothing persisted.
- Invalid `kind` or `status` → `bad_input`.
- `manage_goal update` / `log_journal` with an unknown `goal_id` → `bad_input`.
- `add_event` with `cat='checkin'` but no `goal_id` → allowed (a free-standing reminder) but not
  treated as a goal check-in.
- A check-in whose goal was deleted → `goal_id` is `SET NULL`; the event still fires as a generic
  reminder; journal entries keep their text with null scope.
- Read tools open/close their own read-only connection; a fresh read after a write sees the
  committed value (WAL), same as v5.

## Testing

- **Migration**: `goals` has `why/status/cat/updated_at`; `journal` table + indexes exist;
  `user_events` has `goal_id`; v5 tables intact; existing rows survive.
- **JournalRepository**: insert + `entries` filters (kind / goal_id / range); `setStatus`.
- **GoalsService**: `update` transitions; `all(status:)` filter.
- **Action handlers**: `manage_goal` add/update with cat validation; `log_journal` kind + cat +
  goal_id validation; `add_event` persists `goal_id`; bad input rejected with `bad_input`.
- **Judge payload**: `tick()` includes `active_goals` + `due_check_ins`; fires a tick on a due
  check-in with sparse observations; marks the check-in handled after a nudge.
- **Sidecar tools** (`test/*.test.ts`): `list_journal` shape; `log_journal` / `manage_goal`
  action frames; `summarize_range` includes `recentInsights`.
- **UI**: dashboard renders insight cards + goal journey from the stores; dismiss updates status.

## Build sequence (each its own implementation plan)

Targets a branch off `feat/tailored-data-model` (so it lands as v6 on v5).

1. **Foundation: schema + goals** — migration v6, `GoalRecord`/`GoalsService` extensions,
   `JournalEntry`/`JournalRepository`, `user_events.goal_id`; `manage_goal` + `log_journal`
   tools + handlers + `list_goals`/`list_journal`; persona goal lines. (Pillar 3 core.)
2. **Insights (Notice + Remember)** — persona pattern-noticing + `write_behaviour` distillation;
   `summarize_range.recentInsights`; dashboard **Insights** section + dismiss. (Pillar 2.)
3. **Proactive check-ins** — `add_event` `goal_id`; judge-tick `active_goals` / `due_check_ins`
   injection + fire-on-due + mark-handled; persona check-in lines; dashboard **Goals & journey**
   section. (Pillar 3 proactivity + Pillar 1.)

## Out of scope

- Backend / Supabase sync (local-first, like v5). Cross-device goals/journal is a later effort
  alongside the agent cloud migration.
- A standalone goal detail screen (journey lives on the dashboard).
- Restyling the dashboard to pixel-match the Variant B prototype beyond surfacing the new data;
  broad chart restyling is a separate fast-follow.
- Embedding journal entries into the vector index (possible later for semantic recall).
