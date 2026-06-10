-- ============================================================
-- Togi waitlist table — run this ONCE in your Supabase project:
-- Supabase dashboard → SQL Editor → paste → Run.
-- ============================================================

create table if not exists public.waitlist (
  id          uuid primary key default gen_random_uuid(),
  first_name  text not null,
  last_name   text not null,
  email       text not null unique,
  source      text default 'heytogi.com',
  created_at  timestamptz not null default now()
);

-- If you already created this table with only an email column, add the names:
alter table public.waitlist add column if not exists first_name text;
alter table public.waitlist add column if not exists last_name  text;

-- Row-Level Security: visitors may JOIN (insert) but never READ the list.
alter table public.waitlist enable row level security;

drop policy if exists "anyone can join the waitlist" on public.waitlist;
create policy "anyone can join the waitlist"
  on public.waitlist
  for insert
  to anon
  with check (true);

-- To see who signed up: Supabase → Table editor → waitlist
-- (you, the project owner, can always read it; the public cannot).
