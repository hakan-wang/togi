-- Bogi: paid-status profile table.
--
-- This is the ONLY user-related state the backend touches. It holds no captured
-- activity, no calendar data, no inference content — strictly the subscription
-- entitlement needed to gate `POST /v1/infer`. All real user data lives locally
-- on the Mac.
--
-- Apply with the Supabase SQL editor or `supabase db push`.

create table if not exists public.profiles (
  -- Mirrors the auth user; deleting the auth user removes the profile.
  id                 uuid primary key references auth.users (id) on delete cascade,
  -- Subscription entitlement. Flipped to true only by the Stripe webhook
  -- (service role); the app reads it via GET /v1/account/status.
  paid               boolean not null default false,
  -- Human-readable plan identifier (e.g. Stripe price id or product nickname).
  plan               text,
  -- Stripe customer id, used to reconcile later subscription.* webhook events
  -- back to this user when only the customer id is present.
  stripe_customer_id text,
  updated_at         timestamptz not null default now()
);

-- Look up a profile by Stripe customer id during subscription webhook handling.
create index if not exists profiles_stripe_customer_id_idx
  on public.profiles (stripe_customer_id);

-- ---------------------------------------------------------------------------
-- Auto-provision a profile row whenever a new auth user is created. New users
-- start unpaid; the website checkout + Stripe webhook flip them to paid.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security.
--   * A user may SELECT only their own row (the app reads its own paid flag).
--   * Only the service role may INSERT/UPDATE (the webhook flips `paid`).
--     The service-role key bypasses RLS, so no explicit write policy for it is
--     required; the absence of any anon/authenticated write policy means
--     end users cannot grant themselves a subscription.
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile"
  on public.profiles
  for select
  to authenticated
  using (auth.uid() = id);

-- Note: no insert/update/delete policies for `authenticated` or `anon` are
-- defined on purpose. With RLS enabled and no permissive write policy, those
-- roles cannot modify the table at all. Writes happen exclusively through the
-- backend using the service-role key.

-- Keep `updated_at` fresh on every write.
create or replace function public.touch_profiles_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.touch_profiles_updated_at();
