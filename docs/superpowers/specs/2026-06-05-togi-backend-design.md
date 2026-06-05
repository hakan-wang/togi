# Togi Backend Design

## Scope

Togi is a backend-only MVP for an AI accountability coach based on the product loop in `Bogi app.pdf`.

The backend does not implement a frontend, macOS app, Chrome extension, wake word, always-on monitoring, payments, or team tracking.

The system is built around:

```text
planned_blocks = intention
reality_logs = reality
user_patterns = future planning intelligence
```

## Product Source Of Truth

Features come from `Bogi app.pdf`, not from the tech-stack document. The stack document constrains implementation choices.

Core product behavior:

- Help the user make calendar plans concrete and checkable.
- Ask what actually happened around planned blocks.
- Store the gap between intention and reality.
- Use historical gaps to plan better next time.
- Coach bluntly and usefully, without therapy-style motivation.

## Backend Stack

- Runtime: Next.js API-only app with TypeScript.
- API layer: `app/api/**/route.ts`.
- Database: Supabase Postgres.
- Auth: Supabase Auth, validated server-side.
- Schemas: Zod for request, response, and agent tool contracts.
- Agent runtime: OpenAI Agents SDK for TypeScript.
- LLM calls: OpenAI Responses API through agent services.
- Jobs: Trigger.dev.
- Calendar: Google Calendar API, hidden behind a calendar service boundary.
- Vector memory: pgvector, introduced after structured summaries exist.

No UI routes are required for MVP, except optional health or diagnostics endpoints.

## Backend Modules

```text
src/
  app/api/
  server/
    auth/
    db/
    schemas/
    services/
      calendar/
      agents/
      goals/
      planned-blocks/
      reality-logs/
      patterns/
      summaries/
    jobs/
    lib/
```

The important rule is to keep agent logic out of route handlers. Routes validate input, authorize the user, call services, and return typed responses.

## Database Model

Initial core tables:

- `users`
- `goals`
- `planned_blocks`
- `reality_logs`
- `calendar_connections`
- `agent_runs`
- `user_patterns`

Deferred tables:

- `screen_sessions`
- `screen_observation_summaries`
- `daily_summaries`
- `weekly_summaries`
- `monthly_summaries`

### planned_blocks

Stores the user's intention.

Required fields:

- `id`
- `user_id`
- `calendar_event_id`
- `title`
- `start_time`
- `end_time`
- `intention_text`
- `success_criteria`
- `category`
- `status`
- `created_by`
- `created_at`
- `updated_at`

Every planned block must be checkable. Vague plans such as "be productive" should be rejected or clarified by the Planner Agent.

### reality_logs

Stores what actually happened.

Required fields:

- `id`
- `user_id`
- `planned_block_id`
- `actual_summary`
- `completion_score`
- `deviation_reason`
- `actual_categories_json`
- `confirmed_by_user`
- `source`
- `created_at`
- `updated_at`

The reality log is the product's core artifact. It is user-confirmed truth, not raw AI inference.

### user_patterns

Stores planning intelligence learned from historical behavior.

Required fields:

- `id`
- `user_id`
- `pattern_type`
- `evidence_json`
- `recommendation`
- `confidence`
- `created_at`
- `updated_at`

MVP pattern learning uses deterministic stats plus LLM summarization. No fine-tuning.

### agent_runs

Stores auditability for agent behavior.

Required fields:

- `id`
- `user_id`
- `agent_name`
- `input_json`
- `output_json`
- `status`
- `error`
- `model`
- `started_at`
- `completed_at`

## API Surface

Initial endpoints:

```text
GET  /api/health

GET  /api/goals
POST /api/goals
PATCH /api/goals/:id

GET  /api/planned-blocks
POST /api/planned-blocks
GET  /api/planned-blocks/:id
PATCH /api/planned-blocks/:id
DELETE /api/planned-blocks/:id

GET  /api/reality-logs
POST /api/reality-logs
GET  /api/reality-logs/:id
PATCH /api/reality-logs/:id

POST /api/agents/planner
POST /api/agents/reality-log
POST /api/agents/coach

GET  /api/patterns

GET  /api/calendar/google/connect
GET  /api/calendar/google/callback
POST /api/calendar/google/sync
```

All mutating endpoints require authenticated user context and server-side ownership checks.

## Agent Design

Do not build one giant agent. The backend owns orchestration and calls small agents when needed.

### Planner Agent

Purpose: convert vague intention into checkable planned blocks.

Inputs:

- user request
- calendar availability
- active goals
- relevant user patterns

Output:

- one or more planned blocks with title, time range, intention, success criteria, and category

Rules:

- Every block must be checkable.
- If the user asks for an unrealistic repeat pattern, surface the pattern and propose a better block.
- The agent may draft blocks; the service owns persistence and calendar writes.

### Reality Log Agent

Purpose: turn plan plus user answer into a confirmed reality log.

Inputs:

- planned block
- user's answer
- optional historical context
- optional future screen summary, not MVP

Output:

- actual summary
- completion score
- actual categories
- deviation reason
- clarification question when needed

Rules:

- User confirmation is final.
- AI inference is assistance, not truth.
- Completion score should reflect the success criteria, not generic productivity.

### Coach Agent

Purpose: answer user questions and give blunt planning/accountability feedback.

Inputs:

- planned blocks
- reality logs
- goals
- user patterns
- summaries when available

Rules:

- Be blunt and useful.
- Do not use therapy framing.
- Do not fake motivation.
- Reference concrete evidence from the user's logs.

### Pattern Learner

Phase 2 service/agent hybrid.

Inputs:

- planned blocks
- reality logs
- categories
- completion scores

Output:

- durable user patterns
- evidence
- recommendation
- confidence

MVP pattern learning should start deterministic, then use an LLM to summarize and phrase recommendations.

## Calendar Integration

Start with Google Calendar only.

Calendar service functions:

```text
read_events
create_event
update_event
delete_event
sync_changes
```

The rest of the backend should call Togi's calendar service, not the Google client directly.

Calendar events map to `planned_blocks.calendar_event_id`.

## Jobs

Trigger.dev jobs:

- `block_end_checkin`
- `calendar_sync`
- `pattern_update`
- `daily_summary` deferred
- `weekly_summary` deferred
- `monthly_summary` deferred
- `missed_log_reminder` deferred

MVP only needs job definitions and the first useful job path for block-end check-ins if practical.

## Deferred Screen Lock-In

Screen-share lock-in is not part of backend Phase 1.

When added, backend responsibilities are:

- receive compressed frame batches
- call cheap vision-capable model
- save structured summaries
- delete raw frames quickly
- require user confirmation before writing final reality log

No raw frame storage by default.

## Build Phases

### Phase 1: Core Backend Loop

- Next.js API-only scaffold
- Supabase setup and migrations
- Zod schemas
- goals
- planned blocks
- reality logs
- agent run logging
- Planner Agent
- Reality Log Agent
- Google Calendar service boundary

### Phase 2: Data Bank

- pattern learner
- daily summaries
- weekly summaries
- monthly summaries
- pgvector retrieval if needed
- Coach Agent evidence retrieval

### Phase 3: Lock-In Backend

- screen sessions
- screen observation summaries
- frame batch ingestion
- vision summarization
- raw-frame deletion guarantees

### Phase 4: External Product Support

- voice command ingestion endpoint
- Stripe webhook support
- export/delete data endpoints
- onboarding-support endpoints

## Open Questions

- Should Phase 1 include live Google Calendar OAuth, or should the calendar service start as an interface with a mock provider?
- Should planned blocks be writable without calendar connection, then synced later?
- What exact auth model should be used in local development before Supabase project credentials exist?

## Acceptance Criteria For Phase 1

- A user can create goals.
- A user can create checkable planned blocks.
- A user can create reality logs tied to planned blocks.
- The Planner Agent can turn vague intention into checkable blocks.
- The Reality Log Agent can turn a user answer into a structured log.
- Agent calls are recorded in `agent_runs`.
- Calendar integration is isolated behind a service boundary.
- No frontend UI is implemented.
