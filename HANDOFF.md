# Togi — "Where is my project, and how do I keep it?" (read me first)

Hi Håkan. Short version: **your project is NOT trapped inside anyone's Claude account.**
Claude is just the AI helper. Your actual code lives in real places that are yours:

1. **On your Mac** — the folder `~/togi` (the web app is in `apps/web`).
2. **Your OWN private GitHub** — https://github.com/hakan-wang/togi 🔒 (PRIVATE, only you).
   This is your personal copy. Default branch is **`feat/web-app`** = everything you built.
3. (Also on the shared team repo) https://github.com/er-fo/togi , branch **`feat/web-app`**
   — public, where we worked during the build. Your private copy above is the one you own outright.

Everything we built is saved. Nothing is lost.

> The Claude Code app being signed into someone else's account only decides *who pays for
> the AI*. It does not own or hold your code.

---

## A) Keep working on your OWN Claude account (simplest — nothing to download)
1. In the Claude Code app: **sign out** of the current account, **sign into yours**.
2. Open the **same folder**: `~/togi` (it's already on this Mac).
3. Start a chat and **paste this first message** so the new Claude gets all the context:

   > This is my Togi project. Please read `CLAUDE.md`, then `docs/PROJECT_CONTEXT.md`, then
   > `HANDOFF.md` before doing anything. The app is in `apps/web` on branch `feat/web-app`.
   > When you're done reading, run `cd apps/web && npm install && npm run dev` so I can preview
   > it, and give me a 5-line summary of where the project stands and what you'd do next.

   (`CLAUDE.md` is also read automatically — but pasting the message makes sure.)
4. Done. All the code is right there — keep building, nothing rebuilt from scratch.

## B) Get a fresh copy (new computer, or just to be safe)
Clone YOUR private repo (it'll ask you to sign into GitHub as hakan-wang):
```bash
git clone https://github.com/hakan-wang/togi.git
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
- `apps/web` — the **Next.js web app** (calendar, voice check-ins, categorization,
  insights/memory, sessions, auto check-in). The real product.
- `landing/` — the **heytogi.com** landing page + waitlist (clean/Apple style, deploys via Cloudflare Pages).
- `backend` — cloud functions (Claude proxy, Google Calendar, Stripe).
- `docs` — the **product brief** (`togi_product_and_ui_brief.md`, the source of truth) + specs.
- `archive/macos-screen-tracking` — old hackathon macOS screen-tracking app — **don't build on it**
  (see `archive/README.md`). Read the root `CLAUDE.md` for what's real vs archive.

## The one branch with all the web work
`feat/web-app` — make sure you're on it: `git checkout feat/web-app`.

## ✅ Done: your personal copy already exists
A private copy you fully own is at **https://github.com/hakan-wang/togi** (set up for you).
To make your Mac push there by default instead of the team repo:
```bash
cd ~/togi
git remote set-url origin https://github.com/hakan-wang/togi.git
```
(Right now `origin` = the team repo and `personal` = your private repo. The command above
makes `origin` your private one — optional, only if you want your own copy to be the main one.)
