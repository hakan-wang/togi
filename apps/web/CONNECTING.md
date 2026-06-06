# Connecting Togi to the real services (plain-English guide)

You need to fill in **3 things** in one file. No coding. ~10 minutes.

## The file you paste into
There's a settings file at **`togi/apps/web/.env.local`**. Open it in any text editor
(or tell me and I'll open it). It looks like this — you just fill in the blanks after each `=`:

```
GROQ_API_KEY=
OPENAI_API_KEY=
BACKEND_BASE_URL=https://e7fsq18rqf.execute-api.eu-west-1.amazonaws.com
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_KEY=
```

Rules: paste the value right after the `=`, **no quotes, no spaces**. `BACKEND_BASE_URL`
is already filled — leave it. `OPENAI_API_KEY` and `SUPABASE_SERVICE_KEY` are optional —
leave them blank.

---

## 1. Groq key (turns on real voice → text) — FREE

Groq is free (no credit card) and fast. We use it for speech-to-text.

1. Go to **https://console.groq.com** → sign in (you can use Google or GitHub).
2. Left sidebar → **API Keys** → **"Create API Key"** → name it `Togi` → **Submit**.
3. **Copy** the key (it starts with `gsk_...`). You only see it once.
4. Paste it after `GROQ_API_KEY=`.

(That's it — leave `OPENAI_API_KEY` blank. It's only a paid backup if you ever want it.)

---

## 2. Supabase (saves real check-ins to the cloud)

1. Go to **https://supabase.com** → sign in → **"New project"**.
2. Name it `togi`, set a **database password** (save it somewhere), pick a region near
   Sweden (e.g. **Europe (Stockholm/Frankfurt)**) → **Create new project**. Wait ~2 min.
3. **Get the URL + key:** left sidebar → **Project Settings** (the gear) → **API**.
   - Copy **"Project URL"** → paste after `NEXT_PUBLIC_SUPABASE_URL=`.
   - Under "Project API keys", copy the **`anon` `public`** key → paste after
     `NEXT_PUBLIC_SUPABASE_ANON_KEY=`.
4. **Make the table:** left sidebar → **SQL Editor** → **New query** → paste the block
   below → **Run** (it should say "Success").

   ```sql
   -- Projects: your named endeavors (created only when you declare one).
   create table if not exists projects (
     id uuid primary key default gen_random_uuid(),
     user_id uuid references auth.users on delete cascade,
     name text not null,
     created_at timestamptz default now(),
     unique (user_id, name)
   );
   alter table projects enable row level security;
   create policy "own projects" on projects
     for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

   -- Activities: your reusable verb vocabulary (Togi can add new ones; you can edit later).
   create table if not exists activities (
     id uuid primary key default gen_random_uuid(),
     user_id uuid references auth.users on delete cascade,
     name text not null,
     created_at timestamptz default now(),
     unique (user_id, name)
   );
   alter table activities enable row level security;
   create policy "own activities" on activities
     for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

   -- Real entries: the 4-field model (domain · project · activity · note).
   drop table if exists real_entries;
   create table real_entries (
     id uuid primary key default gen_random_uuid(),
     user_id uuid references auth.users on delete cascade,
     title text,
     domain text not null,
     project text,
     activity text not null,
     note text,
     duration_min int,
     matched_plan_id text,
     matched boolean default false,
     confidence real,
     transcript text,
     started_at timestamptz,
     created_at timestamptz default now()
   );
   alter table real_entries enable row level security;
   create policy "own rows" on real_entries
     for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
   ```

5. **Turn on no-login access:** left sidebar → **Authentication** → **Providers** (or
   "Sign In / Providers") → find **"Anonymous sign-ins"** → toggle it **on** → **Save**.
   (This lets people use Togi without making an account, and it's what lets the app talk
   to the categorizer automatically.)

---

## 3. The categorizer (Claude) — nothing to do

It's already wired to your existing backend (`BACKEND_BASE_URL`). Once step 2's anonymous
sign-in is on, the app sends a sign-in token with each request automatically. If
categorization ever says it's out of quota, that's a 5-per-day free cap on the backend —
tell me and I'll raise it (it's an AWS setting, ~1 line).

---

## When you're done
Save the file, then either:
- **Tell me "done"** and I'll restart the app and test the real spoken check-in for you, **or**
- Restart it yourself: in the Terminal where it's running, press **Ctrl+C**, then run
  `npm run dev` again, and open **http://localhost:3000** in Chrome.

If you'd rather not hunt for these, paste the OpenAI key + Supabase URL + anon key to me in
chat and I'll put them in and test (note: that puts them in our chat history).
