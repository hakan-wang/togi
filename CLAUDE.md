# CLAUDE.md — read this first

You are continuing an existing project called **Togi**. Do NOT start from zero and do NOT
rebuild things that already exist. Before doing any work, read these three files:

1. **`docs/PROJECT_CONTEXT.md`** — the full, factual state of the project: what's built, what's
   stubbed, what's missing, the roadmap, the data model, and known gotchas. **Most important file.**
2. **`HANDOFF.md`** — where the code lives and how the owner (Håkan) works on it.
3. The product specs: **`docs/togi_categorization_spec.md`** and **`docs/togi_insights_spec.md`**.

> Note: a founding doc called `togi_build_addendum.md` is referenced in history but is **NOT in
> this repo**. If you need it, ask Håkan to paste it. Its key decisions are already captured in
> `docs/PROJECT_CONTEXT.md` and are already reflected in the code.

## What Togi is (one line)
A voice-first time/accountability companion: a calendar block ends → a calm notification appears →
the user taps once to talk → one sentence is transcribed + categorized → it lands on the "Real"
timeline → an insight updates. Under 10 seconds.

## The product lives in `apps/web` (a Next.js web app). Branch: `feat/web-app`.
`apps/macos/` is an older, sidelined app. `backend/` is an AWS Lambda proxy (mostly for the macOS app + billing).

## Golden rules (never break these)
- **Never fake** voice/typed capture, categorization, or persistence of Real entries. Everything
  else may be stubbed, but those three must always be real.
- **The mic NEVER auto-starts.** A collapsed notification appears; the mic only goes live on a
  single explicit tap (notification/axolotl or ⌘K). Then: live waveform, pause/resume, Esc cancels,
  "type instead" fallback, Enter submits.
- **Categorization = 4 independent fields**: `domain` (fixed 7-value enum), `project` (reuse
  existing; create new only when the user declares it), `activity` (controlled vocab, AI may add),
  `note` (optional, only if it adds info). Hard rules live in code, not the prompt. See the spec.
- **Insights must pass the "Miss Test"**: only surface patterns the user wouldn't notice
  themselves. See `docs/togi_insights_spec.md`.

## Run it
```bash
cd apps/web
npm install
npm run dev          # http://localhost:3000
```
- Type-check with `npx tsc --noEmit`.
- **Do NOT run `npm run build` while `npm run dev` is running** — it corrupts the `.next` cache
  (symptoms: CSS stops loading, "Cannot find module './xxx.js'"). Fix: stop the server,
  `rm -rf .next`, restart.
- Secrets are in `apps/web/.env.local` (gitignored). On a fresh clone, recreate it from
  `apps/web/.env.local.example` (guide: `apps/web/CONNECTING.md`).

## Stack
Next.js 14.2 (App Router) · React 18.3 · TypeScript (strict: **false**) · plain CSS (design tokens).
**Groq** for both speech-to-text (whisper-large-v3-turbo) and LLM categorization/insights
(llama-3.3-70b-versatile); OpenAI is a fallback. **Supabase** for anonymous auth + storage (RLS).

## Where things are (apps/web)
- `app/api/` — `transcribe/`, `categorize/`, `insights/`, `google/*` (Google Calendar OAuth + events).
- `components/` — `Shell.tsx` (orchestrator), `Calendar.tsx`, `Today.tsx`, `Sessions.tsx`,
  `SessionOverlay.tsx`, `Pages.tsx` (Insights + Settings), `Dock.tsx`, `GcalEventEditor.tsx`, `icons.tsx`, `ds.tsx`.
- `lib/` — `store.ts`, `supabase.ts`, `capture.ts`, `useRecorder.ts`, `data.ts`, `dates.ts`,
  `behavior.ts`, `insightMemory.ts`, `planparse.ts`, `planAdvisor.ts`, `userFacts.ts`,
  `gcal.ts` + `google-server.ts` + `google-calendar-api.ts` (Google Calendar).

For the full status table and roadmap, read **`docs/PROJECT_CONTEXT.md`**.
