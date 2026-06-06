# Connecting Togi to the real services (plain-English guide)

You need to fill in **3 things** in one file. No coding. ~10 minutes.

## The file you paste into
There's a settings file at **`togi/apps/web/.env.local`**. Open it in any text editor
(or tell me and I'll open it). It looks like this — you just fill in the blanks after each `=`:

```
OPENAI_API_KEY=
BACKEND_BASE_URL=https://e7fsq18rqf.execute-api.eu-west-1.amazonaws.com
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_KEY=
```

Rules: paste the value right after the `=`, **no quotes, no spaces**. `BACKEND_BASE_URL`
is already filled — leave it. `SUPABASE_SERVICE_KEY` is optional — you can leave it blank.

---

## 1. OpenAI key (turns on real voice → text)

1. Go to **https://platform.openai.com** and sign in (or sign up).
2. You need a little credit on the account: top-right menu → **Billing** → add ~$5.
   (Whisper is cheap — a check-in costs a fraction of a cent.)
3. Go to **https://platform.openai.com/api-keys** → click **"Create new secret key"** →
   give it a name like "Togi" → **Create** → **Copy** it. It starts with `sk-...`.
   (You only see it once — copy it now.)
4. Paste it after `OPENAI_API_KEY=`.

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
