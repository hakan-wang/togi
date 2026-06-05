# Bogi — Implementation Spec (End-to-End Web Build)

> _"The gap between intention and reality is where your life happens."_
>
> Bogi is a private AI accountability coach. You plan your day into your calendar (intention),
> live it, and then account for what you **actually** did (reality). Every honest check-in
> becomes data in a longitudinal **time data bank** — the real moat. The product is the gap
> between who you said you'd be today and who you actually were.

**Status:** Draft v1 · **Owner:** Erik · **Target market:** Sweden-first, students & "normal people" (ADHD or not)

---

## 0. Decisions locked for this spec

| Decision | Choice | Rationale |
|---|---|---|
| **Tech stack** | Next.js (App Router, TS) + Supabase (Postgres, Auth, Realtime, Edge Functions) | Fastest path to a Sweden-first consumer web MVP; managed Postgres + auth + RLS + realtime out of the box; strong AI ecosystem. Trade-offs in §3. |
| **Calendar** | Two-way **Google Calendar** sync | Lowest adoption friction — users already live in their calendar. Bogi mirrors blocks into its own store so the accountability loop owns the plan/reality model. |
| **Modality** | **Text + voice from day one** | "Hey Boogie" is core to the brand. Browser STT (speech-to-text) for input, TTS for coach replies. |
| **Depth** | Full e2e build spec | Architecture, data model, AI design, API contracts, screens, phased roadmap, deployment. |
| **AI provider** | Anthropic Claude (Opus for coaching/planning reasoning, Haiku for cheap categorization) | Best instruction-following for the "honest, blunt coach" persona; structured tool-use for calendar ops. |

---

## 1. Product definition

### 1.1 The one core feature — the Accountability Loop
The whole product is one loop:

```
PLAN (intention)  →  LIVE  →  ACCOUNT (reality)  →  DATA BANK (compounding context)
   ▲                                                          │
   └──────────────  coach learns your real rhythm  ◀──────────┘
```

1. **Plan** — You tell Bogi (text or voice) what you intend to do. It creates calendar blocks: _"Edit videos for 2h tomorrow."_ Blocks are concrete and checkable — never "be productive."
2. **Live** — Time passes. Blocks start and end.
3. **Account** — When a block ends, Bogi asks: _"You blocked this hour for emailing co-manufacturers. Did you do it? If not, what did you actually do, and why?"_ You answer in your own words.
4. **Data bank** — Each answer is categorized (category → subcategory → description) and stored. Over weeks/months/years it becomes a longitudinal record of your real behavior that no competitor can fast-follow.

### 1.2 The three supporting features
1. **AI assistant / planner** — Natural-language calendar management. Useful, but _not_ why the app exists (this alone already exists, e.g. Motion).
2. **The time data bank** — Categorized, queryable log of reality. Viewable as Today / Week / Month / Year. The real moat. Also a context source the LLM can reason over ("ask AI about your life").
3. **The honest coach** — Not a cheerleader. Knows your goals, reminds you, allowed to be blunt: _"You keep planning to email manufacturers and keep not doing it."_

### 1.3 Beta feature — rhythm-aware planning
Train on the user's historical follow-through. If a user has repeatedly failed to realize a 3-hour editing block, the coach flags it during the next planning session and proposes a realistic alternative. This is **planning informed by reality data**.

### 1.4 Hard product principles (do not violate)
- **Friction is the feature.** Manual accounting is the point, not a bug. We do **not** auto-track screen time. The mindful moment of answering "what did I just do?" _is_ the product.
- **No nagging.** Downloaders already want to log. One gentle nudge per block max; never a wall of notifications. Users can self-initiate logging for any blank stretch ("the blank 5-hour gap").
- **Private, for the user only.** The data is the user's own truth — not for show, not shared, not social. This is a privacy posture and a security requirement (see §11).
- **Concrete intentions only.** The coach's job during planning is to force clarity. Vague blocks break the loop.
- **Not a screen-time blocker.** No walls, no app-blocking, no shame mechanics.

### 1.5 Non-goals (v1)
- No social/sharing/leaderboards.
- No team/corporate features.
- No automatic OS-level screen-time ingestion.
- No native mobile app (web + installable PWA only; native is a later phase).

---

## 2. Personas & core scenarios (acceptance lens)

| Persona | Pain | Loop value |
|---|---|---|
| **The planner who loses the day** (no ADHD) | Calendar says "answered emails," reality was scrolling. The calendar lies to the future self. | Reality log overwrites the comfortable lie. |
| **The ADHD user** | Distractions feel productive (laundry → cleaning → desk). Whole day leaks. Nothing pulls them back. | A gentle end-of-block check-in pulls them back to intention. |
| **The one who can't remember** | No record of their own life; can't tell if they hit their goals. | The data bank _is_ the record. |
| **"Where did my time go?"** | Day evaporates, vague unease, no data. | Zoom-out views explain the evaporation with data. |

These four scenarios are the **acceptance scenarios** — §13 maps tests to them.

---

## 3. Architecture

### 3.1 High-level
```
┌─────────────────────────────────────────────────────────────────┐
│                         Client (Next.js)                         │
│  App Router · React 19 · TS · Tailwind · shadcn/ui · Zustand     │
│  ┌───────────┐ ┌────────────┐ ┌──────────────┐ ┌──────────────┐  │
│  │ Calendar  │ │ Coach chat │ │ Data bank /  │ │ Voice (STT/  │  │
│  │ (plan)    │ │ (loop)     │ │ insights     │ │ TTS) layer   │  │
│  └───────────┘ └────────────┘ └──────────────┘ └──────────────┘  │
└───────────────┬─────────────────────────────────────┬───────────┘
                │ Supabase JS (RLS, Realtime)          │ /api routes (Next route handlers)
┌───────────────▼─────────────────────────────────────▼───────────┐
│                          Supabase                                │
│  Postgres (RLS) · Auth · Realtime · Storage · Edge Functions     │
│  ┌─────────────┐  ┌──────────────────┐  ┌────────────────────┐   │
│  │ Core tables │  │ pgvector (embed) │  │ Scheduled cron      │   │
│  └─────────────┘  └──────────────────┘  └────────────────────┘   │
└───────────────┬─────────────────────────────────────┬───────────┘
                │                                      │
   ┌────────────▼───────────┐            ┌─────────────▼────────────┐
   │ Anthropic Claude API   │            │ Google Calendar API      │
   │ (planner/coach/categ.) │            │ (OAuth, two-way sync,    │
   │ tool-use + structured  │            │  push webhooks)          │
   └────────────────────────┘            └──────────────────────────┘
```

### 3.2 Why this stack (and trade-offs)
- **Next.js App Router** — one codebase for UI + server route handlers (Google OAuth callback, Claude proxy, webhooks). Server Components keep AI keys server-side.
- **Supabase** — Postgres with Row-Level Security gives per-user data isolation cheaply (critical for the privacy promise). Auth, Realtime (for live block transitions), Storage, and Edge Functions (Deno) for cron-driven block-end detection are all included. **Trade-off:** vendor coupling. Mitigation: keep all DB access behind a thin `lib/db` layer and use plain SQL migrations so a move to raw Postgres is mechanical.
- **Claude** — strong persona control for the "blunt honest coach," reliable structured tool-use for calendar mutations. **Trade-off:** cost. Mitigation: Haiku for high-volume categorization/embeddings-adjacent tasks, Opus only for planning/coaching reasoning. Cache the system prompt.
- **Alternatives considered:** T3/tRPC (more type-safety, but we'd rebuild auth + realtime); own Node backend (more control, more ops). Both rejected for MVP speed.

### 3.3 Runtime components
| Component | Responsibility |
|---|---|
| **Web app** | All UI, voice capture, calendar rendering, optimistic updates via Realtime. |
| **`/api/coach`** | Streams Claude responses; orchestrates tool-use (create/move/categorize blocks). |
| **`/api/google/*`** | OAuth flow, token refresh, sync push/pull, channel webhook receiver. |
| **Edge Function `block-watcher`** | Cron (every 1–5 min) → finds blocks that just ended without a reality log → emits a single "check-in due" event (no spam). |
| **Edge Function `sync-google`** | Reconciles Google ⇄ Bogi blocks on webhook + periodic poll. |
| **Edge Function `categorize`** | On new reality log → Claude Haiku assigns category/subcategory/description + embedding. |
| **Edge Function `rollups`** | Nightly aggregation into `time_rollups` for fast Week/Month/Year views. |

---

## 4. Data model (Postgres)

All user-owned tables carry `user_id uuid` and are protected by RLS: `auth.uid() = user_id`.

### 4.1 Core tables
```sql
-- Users live in Supabase auth.users; profile extends it.
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text,
  timezone      text not null default 'Europe/Stockholm',
  locale        text not null default 'sv-SE',
  voice_enabled boolean not null default true,
  coach_bluntness smallint not null default 3,   -- 1 gentle … 5 brutal
  onboarded_at  timestamptz,
  created_at    timestamptz not null default now()
);

-- Google account linkage (tokens encrypted at rest, see §11).
create table google_accounts (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  google_sub     text not null,
  email          text,
  access_token   bytea not null,    -- encrypted
  refresh_token  bytea not null,    -- encrypted
  token_expiry   timestamptz,
  sync_token     text,              -- Google incremental sync token
  channel_id     text,              -- push-notification channel
  channel_expiry timestamptz,
  primary_calendar_id text,
  created_at     timestamptz not null default now()
);

-- A planned block = intention. Mirrors a Google event when synced.
create table blocks (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  google_event_id text,                       -- null if Bogi-native only
  title           text not null,              -- "Edit videos"
  intent          text,                       -- coach-clarified concrete intention
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  source          text not null default 'bogi',   -- 'bogi' | 'google'
  status          text not null default 'planned', -- planned|active|ended|logged|skipped
  planned_category_id uuid references categories(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on blocks (user_id, starts_at);
create index on blocks (user_id, status);

-- The reality log = what actually happened in (or outside) a block.
create table reality_logs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  block_id      uuid references blocks(id) on delete set null,  -- null = free-form gap log
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  raw_text      text not null,            -- user's own words (typed or transcribed)
  did_as_planned boolean,                 -- true|false|null(partial)
  fulfillment   smallint,                 -- 0..100 % of intention realized
  reason        text,                     -- "got tired, scrolled"
  in_control    boolean,                  -- was the gap in your control?
  category_id   uuid references categories(id),
  subcategory   text,
  description   text,
  source        text not null default 'manual', -- manual|voice
  embedding     vector(1536),             -- pgvector, for "ask AI about your life"
  created_at    timestamptz not null default now()
);
create index on reality_logs (user_id, starts_at);

-- 3-level categorization. Categories are user-scoped but seeded from a global taxonomy.
create table categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade, -- null = global seed
  name        text not null,             -- "Activity with friend"
  parent_id   uuid references categories(id),
  kind        text not null default 'leaf', -- 'category'|'subcategory'|'leaf'
  color       text,
  created_at  timestamptz not null default now()
);

-- Goals (month/year) the coach holds you to.
create table goals (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  title       text not null,             -- "Ship the app"
  horizon     text not null,             -- 'week'|'month'|'year'
  period_start date not null,
  period_end   date not null,
  target_metric text,                    -- optional measurable
  status      text not null default 'open', -- open|hit|missed|partial
  created_at  timestamptz not null default now()
);

-- Coach conversation history (the "Hey Boogie" thread).
create table coach_messages (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        text not null,             -- 'user'|'assistant'|'system'
  content     text not null,
  block_id    uuid references blocks(id),     -- if tied to a check-in
  tool_calls  jsonb,
  created_at  timestamptz not null default now()
);

-- Learned behavioral patterns (the beta rhythm feature).
create table rhythm_patterns (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  pattern_key text not null,             -- e.g. 'editing_block_followthrough'
  summary     text not null,             -- "rarely completes >2h editing blocks"
  evidence    jsonb not null,            -- aggregates the claim is built from
  confidence  numeric not null default 0.5,
  updated_at  timestamptz not null default now()
);

-- Precomputed aggregates for fast zoom-out views.
create table time_rollups (
  user_id     uuid not null references auth.users(id) on delete cascade,
  period      text not null,             -- 'day'|'week'|'month'|'year'
  period_start date not null,
  category_id uuid references categories(id),
  planned_minutes int not null default 0,
  actual_minutes  int not null default 0,
  primary key (user_id, period, period_start, category_id)
);
```

### 4.2 Key invariants
- A `block` is **intention**; a `reality_log` is **reality**. The gap between them is the product. Never overwrite a block with reality — store both.
- A `reality_log` can exist with `block_id = null` (the user self-logs a blank gap).
- Categorization is always 3 levels: `category → subcategory → description`.
- RLS denies all cross-user access. No table is readable without `auth.uid() = user_id` (except global category seeds where `user_id is null`).

---

## 5. The Accountability Loop engine (the heart)

### 5.1 Block lifecycle state machine
```
planned ──(now ≥ starts_at)──▶ active ──(now ≥ ends_at)──▶ ended
                                                              │
                              user accounts for it ───────────┤
                                                              ▼
                                                  logged (reality_log created)
ended ──(user marks didn't happen)──▶ skipped
```

### 5.2 Check-in triggering (no-nag policy)
- `block-watcher` Edge Function runs on cron, finds `blocks` where `status='ended'` and no `reality_log`, and creates **one** pending check-in.
- Delivery: in-app badge + at most **one** push/web notification per ended block. Respects quiet hours and a per-user daily nudge cap.
- **Rhythm-aware timing:** if `rhythm_patterns` shows the user takes a break after ~1h of editing, the coach may surface the check-in in that natural break rather than only at block end.
- The user can always open the coach and self-log any time range — no trigger required.

### 5.3 The check-in conversation (coach behavior)
When a block ends, the coach opens with the intention and asks for reality:

> _"You blocked 14:00–15:00 to email co-manufacturers. Did you do it? If not — what actually happened, and why?"_

It then:
1. Parses the user's free-text/voice answer.
2. Extracts `did_as_planned`, `fulfillment %`, `reason`, `in_control`.
3. Categorizes (category → subcategory → description) via Haiku.
4. Writes a `reality_log`, sets `block.status='logged'`.
5. If a gap is detected ("30 min of that, 30 min of LinkedIn"), it splits into multiple logs.
6. Is **honest, not a cheerleader** — but bluntness scales with `profiles.coach_bluntness`.

### 5.4 Free-gap logging
User: _"Hey Boogie, I have no idea what I did 13:00–18:00."_ → Coach walks backward conversationally, creating one or more `reality_logs` with `block_id=null`.

---

## 6. AI design (Claude)

### 6.1 Three Claude "roles"
| Role | Model | Job | Output |
|---|---|---|---|
| **Planner** | Opus | Turn NL into concrete, checkable blocks; force clarity; apply rhythm warnings | tool calls to mutate `blocks` |
| **Coach** | Opus | Run check-ins; extract reality fields; be honest/blunt; hold goals | streamed text + structured extraction |
| **Categorizer** | Haiku | 3-level category + embedding for each reality log | structured JSON |
| **Analyst** | Opus | Answer "ask AI about your life" over the data bank | cited text |

### 6.2 Tool-use surface (planner/coach)
```
create_block(title, intent, starts_at, ends_at)
move_block(block_id, starts_at, ends_at)
delete_block(block_id)
create_reality_log(block_id|null, starts_at, ends_at, raw_text, did_as_planned, fulfillment, reason, in_control)
get_schedule(date_range)
get_rhythm(pattern_key)            -- so planner can warn proactively
get_goals(horizon)
```
All tools execute server-side against Supabase with the user's RLS context. The model never sees other users' data.

### 6.3 Coach system prompt (skeleton)
```
You are Bogi, a private accountability coach. You are NOT a cheerleader.
Your single job: help the user see the gap between what they planned (intention)
and what they actually did (reality), honestly, for themselves only.

Principles:
- Force concrete intentions. Reject "be productive"; ask "for how long, on what?"
- During check-ins, get the truth kindly but bluntly. Bluntness level: {coach_bluntness}/5.
- Never shame, never block, never nag. One ask per block.
- Hold the user to their stated goals: {active_goals}.
- Use their history: {rhythm_patterns}. If they keep failing 3h editing blocks, say so.
- The data is theirs alone. Never imply anyone else will see it.
Language: respond in {locale} (default Swedish), mirror the user's language.
```

### 6.4 Rhythm learning (beta)
Nightly `rollups` job + a weekly Opus pass summarizes follow-through per category into `rhythm_patterns` (e.g. _"completes <50% of editing blocks longer than 2h"_). The planner reads these via `get_rhythm` and warns at plan time: _"Last 4 times you blocked 3h editing you finished ~1h. Want to try 1h + a break?"_

### 6.5 "Ask AI about your life"
Analyst retrieves relevant `reality_logs` via pgvector similarity + structured filters, then answers with citations to specific days/blocks. Strictly read-only; never fabricates logs.

### 6.6 Cost controls
- Cache the system prompt (Anthropic prompt caching).
- Haiku for all categorization/embeddings-adjacent work.
- Batch nightly rollups/rhythm summaries.
- Stream coach responses; cap context to recent thread + retrieved logs.

---

## 7. Voice ("Hey Boogie")

- **Input (STT):** Web Speech API where available; fallback to a server STT (e.g. Whisper via API) for unsupported browsers. Push-to-talk + optional wake-phrase listening in-session.
- **Output (TTS):** Web Speech Synthesis for v1; pluggable to a higher-quality TTS later. Swedish voice default.
- Transcribed text flows into the same coach pipeline as typed input (`reality_logs.source='voice'`).
- Voice is a thin layer over the text loop — no separate AI path. Accessibility: everything voice does is also doable by text.

---

## 8. Google Calendar sync

### 8.1 OAuth & scope
- Scope: `https://www.googleapis.com/auth/calendar.events` (read/write events).
- Store encrypted access/refresh tokens in `google_accounts` (§11). Refresh server-side.

### 8.2 Two-way sync
- **Pull:** On connect, list events from the user's primary calendar → upsert into `blocks` (`source='google'`). Use Google **incremental sync tokens** for deltas.
- **Push:** Bogi-created/edited blocks write back to Google as events.
- **Realtime:** Register a Google **push notification channel**; webhook → `sync-google` Edge Function reconciles deltas. Renew channels before `channel_expiry`. Periodic poll as a safety net.
- **Conflict rule:** last-writer-wins by `updated_at`, with Bogi's `intent`/category metadata preserved (stored Bogi-side, mirrored into the event's extended properties when possible).

### 8.3 Mapping
| Bogi block | Google event |
|---|---|
| `title` | `summary` |
| `starts_at/ends_at` | `start/end` |
| `intent`, `category` | extended private properties |
| `google_event_id` | `id` |

---

## 9. Frontend — screens & UX

### 9.1 Screen inventory
| Screen | Purpose |
|---|---|
| **Onboarding** | Connect Google, set timezone/locale, pick coach bluntness, enable voice, set first goal. |
| **Today (Plan vs Reality)** | The home. Vertical day timeline. Each block shows intention; ended-but-unlogged blocks glow with a "Account for this" CTA. Logged blocks show the gap (planned vs actual side by side). |
| **Coach (Hey Boogie)** | Chat + voice. Planning and check-ins happen here. Streamed responses. |
| **Data bank** | Today / Week / Month / Year toggle. Category breakdown (planned vs actual minutes), gap highlights, "ask AI about your life" box. |
| **Goals** | Month/year goals with the one answer: _did you actually do it? why/why not?_ |
| **Insights / Rhythm** | Learned patterns and the coach's honest read on follow-through. |
| **Settings** | Voice, bluntness, notifications/quiet hours, privacy & data export/delete. |

### 9.2 The signature UI: the gap
Every logged block renders **two lanes**: _Planned_ (what the calendar said) and _Actual_ (what the reality log says), with the delta called out. This is the product made visible — never hide the gap.

### 9.3 Zoom-out views
Week/Month/Year read from `time_rollups`. Each answers: what did this period actually contain, did you hit the goal, and was the miss in your control?

### 9.4 Design tone
Calm, private, honest. Not gamified, no streaks-as-pressure, no shame. Swedish-first copy.

---

## 10. API contracts (Next.js route handlers)

```
POST /api/coach            → { messages, blockId? }  ⇒ SSE stream (text + tool events)
POST /api/blocks           → create/update/delete block (validates, syncs Google)
GET  /api/blocks?from&to   → blocks in range
POST /api/reality-logs     → create reality log (triggers categorize)
GET  /api/data-bank?period&start → rollups + breakdown
POST /api/ask              → "ask AI about your life" (analyst)
GET  /api/google/connect   → start OAuth
GET  /api/google/callback  → finish OAuth, store tokens
POST /api/google/webhook   → Google push channel receiver
POST /api/voice/stt        → fallback server transcription
```
All routes auth-gated via Supabase session; all DB writes pass through RLS.

---

## 11. Privacy & security (a product requirement, not an afterthought)

- **RLS everywhere.** Every user-owned row enforces `auth.uid() = user_id`. No service-role queries in user-facing paths.
- **Token encryption.** Google access/refresh tokens encrypted at rest (libsodium/pgcrypto with a KMS-held key), never sent to the client.
- **AI keys server-side only.** Claude calls go through route handlers/Edge Functions; keys never reach the browser.
- **Data is the user's.** No sharing, no analytics-on-content. Product analytics are event-level (e.g. "loop completed"), never log content.
- **Export & delete.** One-click full export (JSON) and hard account deletion (GDPR — Sweden/EU). Cascade deletes via `on delete cascade`.
- **Embeddings stay private.** pgvector rows are user-scoped under RLS like everything else.
- **Minimal Google scope.** Only `calendar.events`.

---

## 12. Phased roadmap (build order)

### Phase 0 — Foundations (1–1.5 wk)
- Repo, CI, env management, Supabase project, migrations tooling.
- Auth (Supabase email/OAuth), profiles, RLS baseline, `lib/db` abstraction.
- App shell, routing, design system (Tailwind + shadcn/ui), Swedish i18n scaffold.

### Phase 1 — The core loop, text-only (2–3 wk) ← _validation milestone_
- `blocks` + native day timeline (Today screen, plan vs reality lanes).
- Coach chat with Claude planner + tool-use to create/move blocks.
- `block-watcher` + check-in conversation → `reality_logs`.
- Haiku categorization (3-level) + manual recategorize.
- **Exit criteria:** a user can plan a day, get checked in on each block, log reality, and see the gap. The four §2 scenarios are demoable.

### Phase 2 — Google Calendar sync (1.5–2 wk)
- OAuth, encrypted tokens, pull + push, incremental sync, push webhooks, conflict rule.

### Phase 3 — Data bank & zoom-out (1.5–2 wk)
- `time_rollups`, nightly rollup job, Week/Month/Year views, goals, gap analytics.
- "Ask AI about your life" (analyst + pgvector retrieval).

### Phase 4 — Voice (1–1.5 wk)
- Web Speech STT/TTS, push-to-talk, Swedish voice, server STT fallback.

### Phase 5 — Rhythm beta (1–1.5 wk)
- `rhythm_patterns`, weekly summarizer, planner warnings at plan time.

### Phase 6 — Polish, PWA, beta launch (1–2 wk)
- Installable PWA, notifications + quiet hours, export/delete, onboarding, perf, Sweden beta.

> Indicative solo/small-team timeline ≈ **10–14 weeks** to a Sweden beta. Phases 1 alone is the validation MVP.

---

## 13. Testing & acceptance

### 13.1 Scenario-driven acceptance (maps to §2)
1. **Planner-who-loses-the-day:** plan "answer emails 1h" → at block end, log "scrolled 45 min" → Today shows the gap; Week rollup attributes 45 min to the honest category, not "emails."
2. **ADHD user:** block-end check-in arrives in a natural break; user logs the laundry/cleaning detour; coach reflects the pattern without shame.
3. **Can't-remember:** next day, user asks "what did I do yesterday?" → analyst answers from logs.
4. **Where-did-time-go:** self-log a 5h blank gap conversationally → it lands as categorized reality logs.

### 13.2 Test layers
- **Unit:** block state machine, gap computation, category assignment, sync conflict resolution.
- **Integration:** coach tool-use round-trips (mock Claude), Google sync (mock Google), RLS enforcement (cross-user denial tests are mandatory).
- **E2E (Playwright):** onboarding → plan → check-in → log → zoom-out, in Swedish; voice happy-path with mocked STT.
- **AI eval harness:** a fixture set of user utterances → assert correct block mutations, correct reality extraction, and that the coach stays honest (not cheerleading) across bluntness levels.

### 13.3 Guardrail tests
- No-nag: assert ≤1 notification per ended block, quiet-hours respected.
- Privacy: assert no content in analytics events; export/delete completeness.

---

## 14. Observability & ops
- **Logs/metrics:** loop-completion rate (the north-star: % of ended blocks that get a reality log), check-in latency, sync error rate, Claude token cost per active user.
- **Alerting:** Google channel-renewal failures, `block-watcher` lag, RLS policy regressions (CI test gate).
- **Deployment:** Next.js on Vercel (or Supabase-adjacent host); Edge Functions + cron on Supabase; migrations gated in CI.

---

## 15. Success metrics (Sweden beta)
- **North star:** loop-completion rate (ended blocks → reality logged) per active user.
- **Retention proxy:** consecutive days with ≥1 honest log (the data bank only compounds with consistency).
- **Moat metric:** cumulative categorized logs per user (the compounding asset: 1,000 users × ~100 check-ins).
- **Qualitative:** users report they can finally answer "what did I do today/this month?"

---

## 16. Open questions / future
- Native mobile (real "Hey Boogie" wake word) — post-web-validation.
- Apple Calendar / Outlook sync (schema already source-agnostic).
- Optional accountability partner (shared, opt-in) — carefully, without breaking the private-by-default promise.
- Higher-quality TTS persona for the coach voice.
- Pricing (the data bank as the retained value — likely subscription).

---

_Appendix references: product source is `Bogi app.pdf`. Core thesis — "Det enda produkten gör är att visa dig gapet mellan vem du sa att du ville vara idag och vem du faktiskt var." Everything else is mechanics around that._
