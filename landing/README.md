# heytogi.com — Togi landing / waitlist

A simple, static landing page with an email waitlist. No build step — just
plain HTML/CSS/JS. Deploys to **Cloudflare Pages** and serves at **heytogi.com**.

## Files
- `index.html` — the page
- `styles.css` — styling (matches the Togi app brand)
- `app.js` — waitlist form → saves to Supabase
- `config.js` — public Supabase URL + anon key (browser-safe)
- `waitlist.sql` — run this once in Supabase to create the table
- `togi-mascot.png` — the axolotl

## One-time setup
1. **Supabase:** open your project → SQL Editor → paste `waitlist.sql` → Run.
   (Creates the `waitlist` table so signups have somewhere to go.)
2. **Cloudflare Pages:** connect this repo, set the project's **Root directory** to
   `landing`, **Build command** empty, **Output directory** `landing`.
3. Add **heytogi.com** as the custom domain in the Pages project.

## Where signups go
Into the `waitlist` table in your Supabase. See them anytime under
Supabase → Table editor → `waitlist`. Visitors can only add their own email
(Row-Level Security blocks reading the list).

## To change the page
Edit `index.html` / `styles.css`, commit & push — Cloudflare Pages rebuilds
and updates heytogi.com automatically.
