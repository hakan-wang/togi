# Togi — web app (Next.js)

The voice-first web app. Rebuilt pixel-for-pixel from the Claude Design "Togi v2"
(Togi B.html) prototype, with the priority **vertical slice wired for real**:

> a block ends → a collapsed check-in notification appears → one tap on the axolotl
> starts the mic → you speak one sentence → it's categorized (Category › Sub-category
> › Description) → it lands on the **Real** timeline → an insight updates. Under 10s.
> The mic never opens on its own. Typing is always a fallback.

## Run locally

```sh
cd apps/web
npm install
cp .env.local.example .env.local   # fill in keys (see below)
npm run dev                         # http://localhost:3000
```

Use **Chrome** and allow the microphone for the voice path. Without keys the app still
runs: typing works, and categorization falls back to a built-in classifier.

## Environment (`apps/web/.env.local`)

| Var | What it's for | Needed for |
|---|---|---|
| `OPENAI_API_KEY` | Whisper speech-to-text (server-side) | the **voice** path |
| `BACKEND_BASE_URL` | the existing Togi backend (Claude via Bedrock) that categorizes | categorization |
| `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` | sign-in + storing Real entries | real persistence |
| `SUPABASE_SERVICE_KEY` | server-side Supabase (reserved) | optional |

Graceful degradation: no OpenAI key → use "type instead"; backend unreachable/unauthorized
→ falls back to OpenAI then to a keyword classifier; no Supabase → entries persist in
`localStorage`. So the slice is always demoable.

> Backend note: the deployed backend has auth ON (`authDisabled:false`). For categorization
> to use it, sign in via Supabase (the access token is forwarded automatically), or set
> `AUTH_DISABLED=1` on the Lambda for the hackathon. There's also a 5/day free-call cap per
> user — bump `FREE_DAILY_LIMIT` for a day of heavy real use.

## Supabase table

Run in the Supabase SQL editor:

```sql
create table real_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade,
  category text not null,
  sub_category text not null,
  description text not null,
  duration_min int,
  matched_plan_id text,
  matched boolean default false,
  transcript text,
  started_at timestamptz,
  created_at timestamptz default now()
);
alter table real_entries enable row level security;
create policy "own rows" on real_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

## Structure

- `app/` — Next.js App Router (`page.tsx` renders the shell; `api/transcribe`, `api/categorize`)
- `components/` — ported UI: `Shell` (orchestrates the slice in `handleCheckin`), `Today`
  (live check-in card), `Calendar`, `Dock`, `Sessions`, `SessionOverlay`, `Pages`, `icons`, `ds`
- `lib/` — `data` (seed day), `capture`, `useRecorder`, `store` (Supabase + local), `insights`, `supabase`
- `styles/` — the prototype's CSS, copied verbatim (tokens + app stylesheets)

## Faked / deferred (per the build addendum)
Long-term charts, project planning, behavioral-training planning, multi-day views, the
"Hey Togi" wake word, websocket streaming. **Never faked:** voice/typed capture,
categorization, persistence of Real entries.
