-- Free-tier AI metering for Togi. Lives in the SAME Supabase project as profiles.sql
-- (the app's auth project, qpbmrmmnojpqwcaxmqww). One row per user per UTC day.
-- Only the backend service role touches this table.
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  count integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.ai_usage enable row level security;
-- No client policies on purpose: anon/authenticated get nothing; service_role bypasses RLS.

-- Atomically consume one free credit for the day. The UPDATE increments only while the
-- count is under p_max, so it can never run past the cap even under concurrent calls
-- (each call locks the row). Returns whether this call is allowed and the resulting count.
create or replace function public.consume_ai_credit(p_user uuid, p_day date, p_max integer)
returns table(allowed boolean, used integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_used integer;
begin
  insert into public.ai_usage (user_id, day, count)
    values (p_user, p_day, 0)
    on conflict (user_id, day) do nothing;

  update public.ai_usage
     set count = count + 1, updated_at = now()
   where user_id = p_user and day = p_day and count < p_max
   returning count into v_used;

  if found then
    return query select true, v_used;
  else
    select count into v_used from public.ai_usage where user_id = p_user and day = p_day;
    return query select false, coalesce(v_used, p_max);
  end if;
end;
$$;

-- Free quota is enforced server-side only; clients must never call this directly.
revoke all on function public.consume_ai_credit(uuid, date, integer) from anon, authenticated;

-- The webhook maps Stripe -> Supabase by stripe_customer_id when an event lacks our
-- metadata (e.g. invoice.paid renewals), so index it.
create index if not exists profiles_stripe_customer_id_idx
  on public.profiles (stripe_customer_id);
