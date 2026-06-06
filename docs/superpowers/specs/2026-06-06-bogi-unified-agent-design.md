# Bogi Unified Agent — One LangChain Agent over the Local Data Bank

Date: 2026-06-06
Status: Approved direction (brainstorm), pending written-spec review
Related: [Bogi product design](2026-06-06-bogi-datalayer-design.md), [full product plan](../plans/2026-06-06-bogi-full-product-implementation-plan.md)

## Summary

Today Bogi has three separate LLM call sites, each with its own prompt, I/O contract, and
trigger:

| Agent | Trigger | Input | Output | Nature |
|---|---|---|---|---|
| Judge | every ~5 min, background | observations + planned block | strict JSON (segments + nudge) | deterministic, machine-parsed |
| Coach | on demand | user question + prebuilt context | prose | conversational |
| Planner | voice/text command | one utterance | strict JSON (create/move block) | intent extraction |

This design **reconciles all three into one `BogiAgent`** built on **LangChain.js
`create_agent`**, running in a **Node sidecar bundled inside the macOS app**. The agent exposes
**tools over the user's local data bank** that it filters by **keywords + time ranges**, plus
**action tools** for the things only the app can do (nudge, calendar). One persona, one tool
registry, one loop.

The only work that stays a separate call is the bulk **activity segmentation** (turning ~5 min
of raw captured text into labeled time blocks): it remains a cheap structured single-shot
inference, because it is a bulk transformation, not an agentic decision.

It also adds a small, independent improvement: an explicit **focused-window marker** on each
observation, so "this text came from the in-focus window" is recorded rather than assumed.

### Privacy invariant (unchanged)

Raw captured data **never leaves the Mac**. The agent loop and all tool execution run on-device.
Only model turns leave the device — through the existing backend proxy — carrying the messages
and the tool *results* the agent chooses to send. This is the same exposure as today's Coach
context, so there is **no new privacy regression**.

## Goals

- Replace the Coach, Planner, and Judge-nudge call sites with one LangChain.js agent.
- Expose read tools over the local SQLite data bank, filterable by keywords + time ranges, so the
  agent can answer "what did I do yesterday / last week" by querying rather than being spoon-fed a
  today-only context.
- Keep the privacy invariant: raw data stays local; the agent runs on-device.
- Keep the background path cheap: segmentation stays structured; nudging is gated before the agent
  is invoked.
- One persona, defined once: warm, supportive, honest, grounded, no em-dashes.
- Record focus explicitly on observations (tag-only; still capturing the focused window only).

## Non-Goals

- Capturing non-focused / background windows (explicitly deferred; the marker is forward-compatible
  with it).
- Moving the data bank to the cloud or any server-side data storage.
- Routing the bulk segmentation through the agent loop.
- Embeddings/vector search for the new query tools (keyword FTS5 + time ranges only; existing
  `sqlite-vec` search is untouched).
- Replacing the existing backend auth/paywall behavior.

## Architecture

```text
┌───────────────────────────── macOS app (Swift) ──────────────────────────────┐
│                                                                               │
│  Capture (AX, 6s)  ──► SQLite data bank (GRDB, local-only, WAL)               │
│        │                        ▲                                             │
│        │                        │ read-only (FTS5 + time ranges)             │
│        ▼                        │                                             │
│  Segmentation (structured) ─────┘                                            │
│        │  /v1/infer (no tools)                                               │
│        ▼                                                                      │
│  Nudge gate (heuristic) ─┐                                                    │
│                          │  stdio JSON-RPC                                    │
│  Chat UI ────────────────┼───────────────►  Node sidecar (LangChain.js)      │
│  Voice/plan command ─────┘   ◄─────────────  create_agent + tools + memory   │
│        ▲                    action-tool callbacks   │                         │
│        │  (post_nudge, create_block, move_block)    │ BogiProxyChatModel      │
│        └─────────────────────────────────────────── │ /v1/infer (tools)      │
└──────────────────────────────────────────────────── │ ─────────────────────┘
                                                        ▼
                                  Backend Lambda (Node) ──► Bedrock Converse
```

### Components

1. **Sidecar (Node/TS).** Launched by Swift as a child process. Runs one `create_agent` instance
   configured with: the persona `systemPrompt`, the tool registry, a `MemorySaver` checkpointer,
   and a `recursionLimit` to bound loops. Bundled (esbuild) with a Node runtime in the `.app`.

2. **IPC: stdio JSON-RPC.** Line-delimited JSON over the child process's stdin/stdout pipes — no
   open network port. Message kinds:
   - Swift → sidecar: `chat` (message + `threadId`), `plan` (utterance + `threadId`),
     `nudge_tick` (5-min summary + plan + baseline, ephemeral thread).
   - sidecar → Swift: streamed `token` events, final `result`, and `action_call` requests
     (`post_nudge` / `create_block` / `move_block`) that await a Swift `action_result`.
   - lifecycle: `ready`, `health`, `error`.

3. **`BogiProxyChatModel` (custom LangChain `ChatModel`).** Implements the LC chat-model interface
   by POSTing to the backend `/v1/infer`. Translates LC messages + tool definitions ↔ Bedrock
   Converse `toolConfig`, `tool_use`, and `tool_result` content blocks, and surfaces `stopReason`
   and usage. All orchestration stays local; this is the only thing that talks to the network.

### Tools

**Read tools — execute directly against the local SQLite file (read-only, WAL):**

- `search_activity(keywords: string, start?: ISO, end?: ISO, limit?: number)` → list of matching
  segment/observation descriptions, via FTS5 on the text + a `captured_at` range filter. This is
  the "filter by keywords + time ranges" capability.
- `summarize_range(start: ISO, end: ISO)` → totals, on-task/off-task minutes, top categories,
  and plan-vs-reality per block, for the range.
- `list_days(start: ISO, end: ISO)` → per-day on-task/off-task totals (trend questions).
- `list_goals()` → active goals and their targets.

Read tools query the same database file the app writes to, opened **read-only** in WAL mode so
they never block the writer. Rows already filtered at capture time (secure fields, excluded
apps/domains) are never surfaced because they are filtered before storage.

**Action tools — round-trip to Swift over IPC (only the app can perform these):**

- `post_nudge(severity: int, message: string)` → shows the floating mascot nudge.
- `create_block(title, start: ISO, end: ISO)` → creates a calendar block (EventKit / Google).
- `move_block(blockId | match, start: ISO, end: ISO)` → moves an existing block.

Each action tool emits an `action_call` over IPC, awaits Swift's `action_result`, and returns
that result into the agent loop.

### The three triggers, one agent

- **Chat (Coach).** User message → `agent.invoke` with the read tools and a persistent
  `threadId` (conversation memory via the checkpointer). Tokens stream back to the chat UI.
  Retires `CoachService.systemPrompt` and the prebuilt today-only context (the agent now queries
  for what it needs).
- **Plan (Planner).** Voice/text utterance → agent with `create_block` / `move_block` tools →
  performs the action and confirms in prose. Retires `PlannerCommandParser`'s standalone JSON
  contract (the parser's intent shape becomes the action tools' input schemas).
- **Nudge (Judge).** Every ~5 min, *after* the structured segmentation runs, a cheap **heuristic
  gate** (e.g. recent off-task minutes over a threshold) decides whether to invoke the agent at
  all. When invoked, the agent receives the 5-min summary + active plan + a small recent baseline,
  may call read tools to compare against history, and decides whether to call `post_nudge`. Uses
  an **ephemeral thread** so background ticks never pollute chat memory.

### Segmentation (kept structured)

`JudgeService` keeps performing the 5-min segmentation as a plain `/v1/infer` call with **no
tools**, logic unchanged. `JudgePrompt.system` stays, but its nudge instruction is removed (the
agent owns nudging now). Output is still the strict `segments` JSON parsed by `JudgeOutput`.

### Backend change

Extend `POST /v1/infer`:
- Accept an optional `tools` field (Bedrock Converse `toolConfig`).
- Accept `messages` containing `tool_use` / `tool_result` content blocks (not just text).
- Return `stopReason` plus the assistant's content blocks (including any `tool_use`) and usage.
- **Backward compatible:** existing text-only calls (segmentation, and any legacy path) behave
  exactly as today. Auth/paywall logic untouched.

### Focused-window marker (independent piece)

- Add `focused: Bool` to `CaptureSnapshot` (set true; we capture the focused window today).
- Add a `focused` column to `activity_observations` via a schema migration (default `true`).
- Thread it through `JudgeInput.observations` → `JudgePrompt.userJSON` as `"focused": true`.
- Makes focus explicit in the data and the segmentation prompt; forward-compatible with future
  background-window capture.

### Persona

One `systemPrompt` in the sidecar: warm, supportive, honest, grounded strictly in tool results,
**never uses em-dashes**, speaks directly to the user, and never invents data. The current
separate Coach / Planner / Judge-nudge prompt text is folded into this single prompt plus the
tool descriptions. (The warm-tone + no-em-dash hand-edits already committed are superseded by this
prompt; the structured segmentation prompt keeps its own no-em-dash rule.)

### Packaging / ops

- Bundle a Node runtime + the esbuild'd sidecar into `.app` Resources.
- Sign + notarize the embedded `node` helper (entitlements already relax library validation for
  Sparkle; extend as needed for the helper).
- Swift launches the sidecar via `Process`, performs a `health` handshake, and restarts on crash
  with backoff.
- Degradation: sidecar down → chat shows a friendly error, nudges are skipped, planning errors out
  cleanly. The structured segmentation path does not depend on the sidecar.

## Data flow examples

**"What did I do last week?"**
1. Swift sends `chat` over IPC with the question + chat `threadId`.
2. Agent calls `summarize_range(lastWeekStart, lastWeekEnd)` and maybe `list_days(...)` /
   `search_activity("…", start, end)`; tools run read-only SQL locally.
3. Agent composes grounded prose; tokens stream to the chat UI.

**Off-task nudge.**
1. 5-min tick: segmentation runs (`/v1/infer`, no tools) and stores segments.
2. Nudge gate sees off-task minutes over threshold → sends `nudge_tick`.
3. Agent optionally calls `summarize_range`/`search_activity` for context, then calls
   `post_nudge(...)`; Swift shows the mascot nudge and returns the result.

**"Move my editing block to 3pm."**
1. Swift sends `plan` with the utterance.
2. Agent resolves the relative time, calls `move_block(...)`; Swift performs the EventKit/Google
   change and returns success; agent confirms in prose.

## Error handling

- `recursionLimit` on the agent bounds runaway tool loops.
- Read-tool failures (bad range, empty DB) return empty/typed results; the agent reports "I don't
  have data on that yet" rather than inventing.
- Action-tool failures return a typed error over IPC; the agent surfaces it honestly.
- Proxy/model errors propagate to Swift; chat shows an error, nudges/plans fail cleanly.
- Sidecar crash → Swift restarts it; in-flight requests fail with a retryable error.

## Testing

- **TS tool tests:** seed a SQLite fixture; assert `search_activity` keyword + time-range
  correctness, `summarize_range` aggregation, `list_days`, `list_goals`.
- **`BogiProxyChatModel` translation tests:** LC messages + tools ↔ Converse payloads, including
  `tool_use` / `tool_result` round-trips and `stopReason`.
- **Backend tests:** `/v1/infer` with `tools` returns `tool_use`; tool_result messages round-trip;
  text-only calls unchanged (regression).
- **Swift IPC tests:** `action_call` callbacks invoke EventKit / nudge stubs and return results.
- **Migration test:** `focused` column added with correct default; `JudgePrompt.userJSON` emits
  `"focused"`.
- **Integration smoke:** "what did I do last week" drives `search_activity` / `summarize_range`
  and returns grounded prose; an off-task scenario produces a `post_nudge`.

## Open questions / risks

- **Node runtime size + notarization** of an embedded helper is the main packaging risk; needs an
  early spike to confirm the signing story before deep implementation.
- **SQLite cross-process reads:** confirm GRDB writes in WAL so the read-only sidecar never blocks
  the writer; otherwise route reads back through Swift.
- **Agent latency on chat** (multi tool round-trips through the proxy) — acceptable for on-demand
  chat; the nudge gate protects the background path.
