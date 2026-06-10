-- Bogi auth/paid gate. Supabase stores ONLY accounts + paid status (no user data).
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  paid boolean not null default false,
  plan text,
  stripe_customer_id text,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Users may read their own profile; service_role (backend) bypasses RLS.
drop policy if exists "own profile read" on public.profiles;
create policy "own profile read" on public.profiles
  for select using (auth.uid() = id);

-- Auto-create a profile row on signup (unpaid by default).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
