# CLAUDE.md — read this first

You are continuing **Håkan's Togi**. Do NOT start from zero and do NOT rebuild things that
already exist.

> ⚠️ **This repo is messy on purpose-for-now.** About half of what's in here was copied
> (mirrored) from the team's old repo (`er-fo/togi`) — branding, assets, and a hackathon
> feature that Michelle & Erik built. **A lot of it does NOT apply to Håkan's Togi.** This file
> tells you what's real and what's archive so you don't get misled.

## 0. The single source of truth
**`docs/togi_product_and_ui_brief.md`** — read it first. It defines what Togi is, the core
value, the features, and the UI. If anything elsewhere contradicts the brief, the **brief wins**.

## 1. What Togi is (from the brief)
A private, **voice-first** assistant that helps you **plan your day**, then **record what you
actually did**. The product lives in the gap between intention and reality. The headline is
**clarity + a private behavioral data bank about how you spend your time** — *not* "accountability"
(accountability is just the mechanism that collects your honest input). Short-term: where did today
go? Long-term: a compounding record of your life, for you.

## 2. Brand & UI direction (IMPORTANT — this changed)
- **Clean, neutral, calm — think Apple.** Lots of whitespace, crisp type, one restrained accent.
- **NOT** the old "dreamy blue-sky / pastel / playful" look. That aesthetic is Michelle's and is
  **out**. If you see sky gradients (`--sky-*`), pastel tokens, or "Bogi" branding, that's the old
  look to replace, not to copy.
- **"togi — to sharpen."** Sharp, quiet, confident. The name has nothing to do with sky-blue.
- **The axolotl mascot is a temporary placeholder only** (kept until a real persona is decided).
  Use it small and understated; it is **not** the final brand.

## 3. What's REAL vs ARCHIVE in this repo
**Real (Håkan's Togi — build here):**
- `apps/web/` — the Next.js web app (the actual product). Branch: **`feat/web-app`**.
  ⚠️ Its current *styling* still uses the old blue-sky tokens — restyling it to the clean/Apple
  look is a planned, separate task (not done yet).
- `landing/` — the **heytogi.com** landing page + waitlist (already clean/Apple style). Static
  HTML/CSS/JS, deployed via **Cloudflare Pages**.
- `backend/` — stateless AWS Lambda proxy (billing, Claude on Bedrock). Useful infra.
- `docs/` — specs + the brief.

**Archive (Michelle/Erik hackathon — do NOT build on, see `archive/README.md`):**
- `archive/macos-screen-tracking/` — the **screen-tracking** experiment: a floating desktop icon
  that screenshots your screen every few seconds to judge if you're on-task. This is a
  *super-beta, far-future* idea, **not** what we're building now. Treat as read-only history.
- The ~30 mirrored branches (`devin/bogi-*`, `erik-*`, `michelle*`, etc.) — kept as an untouched
  archive of the team's hackathon work. Don't merge them into `feat/web-app`.

## 4. Golden rules (for the web app)
- **Never fake** voice/typed capture, categorization, or persistence of real entries.
- **The mic NEVER auto-starts.** A calm notification appears; the mic goes live only on one
  explicit tap (or ⌘K). Then: live waveform, pause/resume, Esc cancels, "type instead", Enter submits.
- **Insights must pass the "Miss Test"** — only surface patterns the user wouldn't notice. See
  `docs/togi_insights_spec.md`.
- **Categorization:** the *code today* uses 4 independent fields (`domain` / `project` / `activity`
  / `note`, see `docs/togi_categorization_spec.md`). The *brief* (§6.5) describes 3 levels
  (Category / Sub-category / Description). **These don't fully match — ask Håkan which model to
  follow before changing categorization.**

## 5. Run it
```bash
cd apps/web && npm install && npm run dev     # http://localhost:3000
```
- Type-check with `npx tsc --noEmit`. **Do NOT run `npm run build` while `npm run dev` is live**
  (it corrupts `.next`; symptoms: CSS stops loading / "Cannot find module './xxx.js'"). Fix: stop
  dev, `rm -rf apps/web/.next`, restart.
- Landing preview: `cd landing && python3 -m http.server 4321`.
- Secrets in `apps/web/.env.local` (gitignored). The landing's `config.js` carries only the
  **public** Supabase anon key (browser-safe).

## 6. Stack
Next.js 14.2 (App Router) · React 18.3 · TS (strict false) · plain CSS tokens. **Groq** for STT
(whisper-large-v3-turbo) + LLM (llama-3.3-70b-versatile), OpenAI fallback. **Supabase** (anon auth
+ RLS storage). Landing waitlist → Supabase `waitlist` table.

## 7. Where things are (apps/web)
- `app/api/` — `transcribe/`, `categorize/`, `insights/`, `google/*`.
- `components/` — `Shell.tsx` (orchestrator), `Calendar.tsx`, `Today.tsx`, `Sessions.tsx`,
  `SessionOverlay.tsx`, `Pages.tsx`, `Dock.tsx`, `GcalEventEditor.tsx`, `EventEditor.tsx`, `icons.tsx`, `ds.tsx`.
- `lib/` — `store.ts`, `supabase.ts`, `capture.ts`, `useRecorder.ts`, `data.ts`, `dates.ts`,
  `behavior.ts`, `insightMemory.ts`, `planparse.ts`, `planAdvisor.ts`, `userFacts.ts`, `gcal.ts` + `google-*`.

For the full status table and roadmap, read **`docs/PROJECT_CONTEXT.md`** (but the **brief** outranks it on product/UI).
