# Togi — "Where is my project, and how do I keep it?" (read me first)

Hi Håkan. Short version: **your project is NOT trapped inside anyone's Claude account.**
Claude is just the AI helper. Your actual code lives in two real places that are yours:

1. **On your Mac** — the folder `~/togi` (the web app is in `apps/web`).
2. **On GitHub** — https://github.com/er-fo/togi , branch **`feat/web-app`**.
   It's **public**, and every change was pushed using **your own GitHub account (hakan-wang)**.
   Everything we built is saved there. Nothing is lost.

> The Claude Code app being signed into someone else's account only decides *who pays for
> the AI*. It does not own or hold your code.

---

## A) Keep working on your OWN Claude account (simplest — nothing to download)
1. In the Claude Code app: sign out of the current account, sign into **your** account.
2. Open the **same folder**: `~/togi` (it's already on this Mac).
3. Done. All the code is right there — keep building.

## B) Get a fresh copy (new computer, or just to be safe)
```bash
git clone https://github.com/er-fo/togi.git
cd togi/apps/web
npm install
npm run dev      # then open http://localhost:3000
```

## C) ⚠️ Your secret keys are NOT on GitHub (on purpose, for safety)
The file `apps/web/.env.local` (your **Groq** key + **Supabase** URL/key) is deliberately
kept out of GitHub. It already exists on **this** Mac, so option A needs nothing.
If you clone to a **new** computer, recreate it: copy `apps/web/.env.local.example` to
`apps/web/.env.local` and paste your keys (full guide: `apps/web/CONNECTING.md`).

---

## What's in the repo
- `apps/web` — the **Next.js web app** (everything we built: calendar, voice check-ins,
  categorization, insights/memory, sessions, auto check-in).
- `apps/macos` — the older macOS app.
- `backend` — cloud functions (Claude proxy, Google Calendar, Stripe).
- `docs` — the specs (`togi_categorization_spec.md`, `togi_insights_spec.md`).

## The one branch with all the web work
`feat/web-app` — make sure you're on it: `git checkout feat/web-app`.

## (Optional) Make a copy you 100% own on your personal GitHub
If you want it under your own account instead of the shared `er-fo` org, see the note your
assistant added below / ask Claude to "push a copy to my personal GitHub".
