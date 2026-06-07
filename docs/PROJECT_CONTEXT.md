# Togi — Project Context & Continuation Plan

> **Purpose of this file.** This is the single source of truth for picking up Togi where we left
> off. It is written to be factual (verified against the actual code on 2026-06-07), not
> aspirational. If you are a fresh Claude session: read this end to end before changing anything.
> If something here disagrees with the code, the code wins — update this file.

---

## 1. What Togi is

Togi is a voice-first time & accountability companion. The one path that must always work
("the vertical slice"):

> A planned calendar block ends → Togi shows a **calm, collapsed notification** → the user
> **taps once** to start the mic → says one sentence → it's transcribed → categorized into
> **domain › project › activity › note** → it lands on the **Real** timeline → an **insight**
> updates. All in under ~10 seconds.

Two timelines sit side by side: **Plan** (what you intended) and **Real** (what actually happened).
Over time, Togi learns your patterns and surfaces **insights you wouldn't notice yourself**, then
uses them when helping you plan.

---

## 2. Founder-confirmed decisions (the rules that override everything)

These came from Håkan (the founder/owner) during the build and are reflected in the code:

1. **Never fake** three things: voice/typed **capture**, **categorization**, and **persistence**
   of Real entries. Everything else may be stubbed for the demo.
2. **Mic never auto-starts.** The block-end notification is collapsed and calm. The mic goes live
   ONLY on a single explicit tap (the notification/axolotl, or ⌘K / hotkey). Once live: live
   waveform, pause/resume, **Esc** cancels, **"type instead"** fallback, **Enter** submits.
3. **Categorization is 4 independent fields** (see `docs/togi_categorization_spec.md`):
   - `domain` — fixed 7-value enum (below). Always exactly one.
   - `project` — optional; **reuse** an existing project by fuzzy match; create a NEW one only when
     the user explicitly declares it. Never invent projects.
   - `activity` — a reusable controlled-vocabulary label; AI may add new ones.
   - `note` — optional one-liner, only if it adds information beyond the other three.
   - **Hard rules live in code, not the prompt.**
4. **Insights must pass the "Miss Test"** (see `docs/togi_insights_spec.md`): only surface
   emergent, cross-day, quantified patterns the user couldn't easily see themselves. Never restate
   a single event back to them.
5. **Plans are not force-categorized** — only real check-ins are. Planning copy is encouraging
   ("Plan smarter with Togi"), never accountability-shaming.
6. **Today's Real starts empty** — it fills from the user's own check-ins, not seeded examples.
7. The **7 fixed domains**: `Work`, `Study`, `Health`, `Social`, `Errands & life admin`,
   `Leisure`, `Distraction`.

---

## 3. Where everything lives

- **On Håkan's Mac:** `~/togi` (user account `hth.wang`). The web app is in `apps/web`.
- **Personal private GitHub (owned by Håkan):** https://github.com/hakan-wang/togi 🔒
  Default branch `feat/web-app`. This is the copy he owns outright.
- **Shared team GitHub (public):** https://github.com/er-fo/togi — where the build happened.
- **Working branch:** `feat/web-app` (all web-app work is here; `main` is older).
- **Git remotes on the Mac:** `origin` → er-fo/togi, `personal` → hakan-wang/togi.
- **Secrets:** `apps/web/.env.local` (gitignored; on the Mac only — NOT in any GitHub repo).

---

## 4. Tech stack & architecture

- **Frontend/app:** Next.js **14.2.15** (App Router) · React **18.3.1** · TypeScript **5.6**
  (`strict: false`) · plain CSS with design tokens (ported pixel-for-pixel from the "Claude Design"
  prototype). Dependencies are deliberately minimal: `next`, `react`, `react-dom`,
  `@supabase/supabase-js`, `openai`.
- **Speech-to-text:** **Groq** Whisper (`whisper-large-v3-turbo`), auto-detects Swedish + English.
  Falls back to **OpenAI** Whisper (`whisper-1`) if `OPENAI_API_KEY` is set; otherwise returns a
  clear "type instead" error.
- **LLM (categorization + insights):** **Groq** `llama-3.3-70b-versatile` (temp 0). Falls back to
  **OpenAI** `gpt-4o-mini`, then to a deterministic keyword classifier as a last resort. Both Groq
  and OpenAI are reached through the **OpenAI SDK** (Groq via `baseURL=https://api.groq.com/openai/v1`).
- **Auth + storage:** **Supabase** — anonymous sign-in (no login screen), Row-Level Security per
  `user_id`. The app is offline-first: if Supabase env vars are missing, it runs on localStorage.
- **Backend (`backend/`):** a stateless **AWS Lambda** (API Gateway) that proxies Claude on
  **Bedrock** and handles **Stripe** billing + free-tier metering. Built primarily for the macOS
  app. **The web app's `/api/categorize` currently calls Groq directly, not this backend** —
  `BACKEND_BASE_URL` exists in env but the live categorization path is Groq. (Worth revisiting if
  you want one shared categorizer.)

**Graceful degradation chain** (important — the app never hard-crashes on a missing key):
- No Groq key → OpenAI → built-in keyword classifier.
- No Supabase → localStorage only.

---

## 5. Feature status — REAL vs STUBBED vs MISSING

Verified against the code. "REAL" = live data / real API / real DB. "STUBBED" = hardcoded/scripted
(often intentionally, for the demo). "MISSING" = not built.

| Area | Status | Files | Notes |
|---|---|---|---|
| Voice recording (mic) | **REAL** | `lib/useRecorder.ts` | Native `MediaRecorder`, real permission flow, live level meter. Never auto-starts. |
| Transcription | **REAL** | `app/api/transcribe/route.ts` | Groq Whisper primary, OpenAI fallback, SV/EN auto-detect. |
| Categorization (4-field) | **REAL** | `app/api/categorize/route.ts`, `lib/capture.ts`, `lib/data.ts`, `lib/store.ts` | Groq LLM; hard enum/validation/fuzzy-match in code; clarify question if confidence < 0.6. |
| Persistence of Real entries | **REAL** | `lib/store.ts`, `lib/supabase.ts` | Supabase `real_entries` (RLS) + localStorage mirror/fallback (`togi.real_entries.v3`). |
| Project/activity vocabulary | **REAL** | `lib/store.ts` | Supabase `projects`/`activities` + localStorage; seeded once from `STARTER_ACTIVITIES`. |
| Behavioral stats engine | **REAL** | `lib/behavior.ts` | Computes follow-through, slips, estimation error, distraction, focus windows. Evidence floors enforced. |
| Insight memory | **REAL** | `lib/insightMemory.ts` | Lifecycle candidate→active→fading→retired; dedup + reconcile; localStorage `togi.insights.v1`; surfaces top 5. |
| Insight AI pass | **REAL** | `app/api/insights/route.ts` | Groq LLM phrases/judges; Miss Test enforced in prompt; 6 insight families. |
| Calendar dates/clock | **REAL** | `lib/dates.ts`, `components/Calendar.tsx` | Real local dates, rolling 7-day strip (3 back→today→3 fwd), real now-line (updates ~15s). |
| Voice planning | **REAL** | `Shell.tsx handlePlan`, `lib/planparse.ts`, `lib/planAdvisor.ts` | Transcribe → parse time/duration → consult memory (may move/pad block) → save to plan. |
| User facts | **REAL** | `lib/userFacts.ts` | wake/sleep/planning times, autoCheckin, minGapMin; respected in planning; localStorage. |
| Auto check-in (blank gaps) | **REAL** | `lib/userFacts.ts`, `Sessions.tsx`, `Pages.tsx` | Splits gaps into hourly windows; Settings toggle + min-gap. Affects Sessions list (no push notifications yet). |
| Sessions list | **REAL** | `components/Sessions.tsx` | Due/scheduled/done derived from real plan + clock. |
| Auth (anon) | **REAL** | `lib/supabase.ts` | Silent `signInAnonymously()`, idempotent, safe fallback. |
| **Google Calendar** | **CODE-COMPLETE, NOT CONFIGURED** | `lib/gcal.ts`, `lib/google-server.ts`, `lib/google-calendar-api.ts`, `app/api/google/*`, `components/GcalEventEditor.tsx` | Full server-side OAuth, encrypted token storage, read+create+update+delete. **Needs setup, not code** — see §8. |
| Session overlay conversation | **STUBBED** | `components/SessionOverlay.tsx` | Hardcoded dialogue tree (check-in/plan/ask/self). The *real* check-in is `Today.tsx`; this overlay is a scripted fallback. |
| Insights "data bank" charts | **STUBBED (by design)** | `components/Pages.tsx` | Weekly bars + "long view" numbers are mock; explicitly allowed to be faked. |
| Demo seed data | **STUBBED (by design)** | `lib/data.ts`, `lib/behavior.ts seedHistory()` | `PLAN`, `REAL_SEED`, `DISCREPANCIES`, etc. + a deterministic 14-day history that powers the insight engine before real data accrues. |
| Notification / phone-call toggles | **MISSING (cosmetic toggle only)** | `components/Pages.tsx` | "Remind me", "call me", "hourly nudge", "reduce motion" are state-only; no backend. |
| Billing wired into the web UI | **MISSING (backend exists)** | `backend/`, `TOGI_PAYWALL_SETUP.md` | Stripe checkout/portal/webhook + free-tier metering built on the backend; **not wired into the web app's UI**. |
| Deploy (Vercel) | **MISSING** | — | Not deployed yet; runs locally. |

---

## 6. Data model & persistence details

**localStorage keys** (offline-first mirror/fallback): `togi.real_entries.v3`, `togi.plan.v2`,
`togi.activities.v1`, `togi.projects.v1`, `togi.insights.v1`, `togi.facts.v1`.

**Supabase tables the web app uses** (create with the SQL in `apps/web/CONNECTING.md`):
- `real_entries` — `id` (uuid default `gen_random_uuid()`), `user_id`, `title`, `domain`,
  `project`, `activity`, `note`, `duration_min`, `matched_plan_id`, `matched`, `confidence`,
  `transcript`, `started_at`, `created_at`. **Do not send a client-generated `id`** — let Postgres
  default it (a past bug: sending `live-...` strings broke the uuid column).
- `projects` — `user_id`, `name`, `created_at`.
- `activities` — `user_id`, `name`, `created_at`.

**Supabase tables for backend features** (SQL in `backend/supabase/`):
- `profiles.sql` — `id`, `paid`, `plan`, `stripe_customer_id`, `updated_at` (billing status).
- `ai_usage.sql` — per-user/per-day counter + `consume_ai_credit()` RPC (free-tier metering, 5/day).
- `google_calendar.sql` — `google_calendar_connections` (encrypted OAuth tokens; RLS with **no**
  client policies, server-role only). **Must be run before Google Calendar will work.**

All tables use RLS keyed on `user_id`.

---

## 7. Environment variables (names only — values are in `.env.local`, never commit them)

Web app (`apps/web/.env.local`, template in `.env.local.example`):
- `GROQ_API_KEY` (server) — speech-to-text + LLM. Free tier; rotate anytime in the Groq console.
- `OPENAI_API_KEY` (server, optional) — fallback STT/LLM.
- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (public — anon key is browser-safe).
- `SUPABASE_SERVICE_KEY` (server) — needed for Google token storage + backend features.
- `BACKEND_BASE_URL` (public) — AWS Lambda proxy (not on the live web categorize path today).
- Google Calendar: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` (server), `GOOGLE_REDIRECT_URI`
  (optional; defaults to `${origin}/api/google/callback`), `TOKEN_ENC_KEY` (server; generate with
  `openssl rand -base64 48`).

---

## 8. Google Calendar — exact remaining steps (code is DONE; this is config only)

The full integration is already written (OAuth start/callback/status/events/disconnect routes,
encrypted server-side token storage with auto-refresh, an event editor UI, and Plan-view merging of
Google events). To turn it on:

1. **Create a Google Cloud OAuth app** (see `apps/web/SETUP_GOOGLE_CALENDAR.md` for click-by-click):
   - New project in https://console.cloud.google.com → enable **Google Calendar API**.
   - OAuth consent screen (External; add yourself as a test user). Scopes: `calendar.events`,
     `calendar.calendarlist.readonly`, `openid`, `email`.
   - Create an **OAuth client (Web application)**. Authorized redirect URI:
     `http://localhost:3000/api/google/callback` (add your production URL later).
   - Copy the **Client ID** and **Client Secret**.
2. **Add to `apps/web/.env.local`:** `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`,
   `TOKEN_ENC_KEY` (`openssl rand -base64 48`), and make sure `SUPABASE_SERVICE_KEY` is set.
3. **Run the SQL** `backend/supabase/google_calendar.sql` in Supabase → SQL editor (creates
   `google_calendar_connections`). **Blocking** — token storage fails without it.
4. **Restart** `npm run dev`, then Togi → **Settings → Calendar → Connect**. Complete consent.
   Today's events should appear in the Plan view; create/edit/delete from Togi should sync to Google.

Not built (future): multi-calendar support, watching for external Google edits (polling/webhooks),
all-day events, attendees, OAuth verification to go fully public (currently "Testing" mode, ≤100 users).

---

## 9. Roadmap — suggested next steps (rough priority)

1. **Turn on Google Calendar** (§8) — highest leverage; code is already done.
2. **Wire billing into the web UI** — backend (Stripe + `ai_usage` metering) exists; the web app
   needs upgrade/paywall UI + calls to `/v1/account/status` and checkout. See `TOGI_PAYWALL_SETUP.md`.
3. **Replace the scripted `SessionOverlay`** with a real LLM conversation (the live check-in in
   `Today.tsx` is already real; the overlay is the remaining scripted surface).
4. **Real insights from accumulated data** — today the engine seeds a 14-day demo history so
   insights exist on day one; once real entries accrue, prefer real history over the seed.
5. **Notifications backend** — make the "remind me / call me / hourly nudge" toggles do something
   (web push, or native if/when packaged). Currently cosmetic.
6. **Deploy to Vercel** and point a domain. Add production URLs to Supabase auth + Google OAuth.
7. **Replace remaining mock charts** in the Insights "data bank" with live aggregates.

---

## 10. Known gotchas (learned the hard way)

- **Don't run `npm run build` while `npm run dev` is live** — it clobbers `.next` (symptoms: CSS
  stops loading, `Cannot find module './xxx.js'`). Fix: stop dev, `rm -rf apps/web/.next`, restart.
  Use `npx tsc --noEmit` to type-check instead of building during dev.
- **Supabase `real_entries` insert:** never send a client `id`; let Postgres default the uuid.
- **Check-in placement:** a generic "now" check-in glues to the most-recently-ended unlogged
  ("due") block, not the in-progress one. Future/aligned real entries are offset on the X axis
  (`.real-pos.aligned` → `translateX(12px)`) so Plan and Real read as two columns.
- **Anon auth** can be disabled in Supabase; it must be **on** for the app to sign users in silently.

---

## 11. Specs & docs map

- `docs/togi_categorization_spec.md` — the 4-field categorization contract (domains, project/activity
  rules, starter vocabulary, system prompt, examples).
- `docs/togi_insights_spec.md` — the behavioral-insights "moat": the Miss Test, the 6 insight
  families, the memory lifecycle, the hybrid (code computes / AI phrases) pipeline.
- `apps/web/CONNECTING.md` — plain-English setup (Groq key, Supabase, the SQL for the 3 web tables).
- `apps/web/SETUP_GOOGLE_CALENDAR.md` — Google Calendar OAuth setup, click by click.
- `apps/web/README.md` — web app overview + structure.
- `TOGI_PAYWALL_SETUP.md` — Stripe billing + free-tier plan and go-live steps.
- `backend/README.md` — the Lambda/Bedrock/Stripe proxy.
- `HANDOFF.md` — ownership + how to switch Claude accounts and run.
- **Missing from the repo:** `togi_build_addendum.md` (the founding spec Håkan pasted in chat). Its
  decisions are summarized in §2 above; if you need the original, ask Håkan to paste it.
