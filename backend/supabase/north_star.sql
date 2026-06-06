-- Togi North Star — the user's single apex life-goal, stated in onboarding.
--
-- This is the ONE exception to Togi's local-only rule: it syncs so it persists across devices
-- and seeds the AI everywhere. It holds ONLY user-stated goal text — never capture / AX /
-- behavioral data. The schema makes that physically true: text columns only, one row per user,
-- isolated by RLS. The Mac app writes it directly via PostgREST with the user's access token
-- (the same pattern SupabaseAuth already uses); it never goes through the AWS inference proxy.

create table if not exists public.north_star (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  text        text not null,
  why         text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id)                       -- one North Star per user
);

alter table public.north_star enable row level security;

-- A user may read/insert/update/delete ONLY their own North Star row.
drop policy if exists "own north_star select" on public.north_star;
create policy "own north_star select" on public.north_star
  for select using (auth.uid() = user_id);

drop policy if exists "own north_star insert" on public.north_star;
create policy "own north_star insert" on public.north_star
  for insert with check (auth.uid() = user_id);

drop policy if exists "own north_star update" on public.north_star;
create policy "own north_star update" on public.north_star
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own north_star delete" on public.north_star;
create policy "own north_star delete" on public.north_star
  for delete using (auth.uid() = user_id);

-- Keep updated_at honest on every write (supports last-write-wins sync).
create or replace function public.touch_north_star_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists north_star_set_updated_at on public.north_star;
create trigger north_star_set_updated_at
  before update on public.north_star
  for each row execute function public.touch_north_star_updated_at();
