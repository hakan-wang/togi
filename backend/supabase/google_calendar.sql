-- Togi — Google Calendar OAuth connections (one row per user).
-- SECURITY: tokens are sensitive. RLS is ENABLED but NO client policy is granted,
-- so the browser (anon/authenticated key) can neither read nor write this table.
-- Only the Next.js server routes touch it, using the service_role key (which bypasses
-- RLS). The refresh_token is additionally encrypted at rest (AES-256-GCM) by the app.
create table if not exists public.google_calendar_connections (
  user_id uuid primary key references auth.users(id) on delete cascade,
  google_email text,                       -- which Google account is connected (for display)
  access_token text not null,              -- encrypted (AES-GCM) short-lived access token
  refresh_token text,                      -- encrypted (AES-GCM) long-lived refresh token
  expires_at timestamptz not null,         -- when the access token expires
  scope text,                              -- granted scopes
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.google_calendar_connections enable row level security;

-- Intentionally NO policies: the anon/authenticated client is fully blocked.
-- The server uses SUPABASE_SERVICE_KEY (service_role) which bypasses RLS.
-- (Drop any leftover permissive policies if this was run before.)
drop policy if exists "own connection" on public.google_calendar_connections;

-- keep updated_at fresh
create or replace function public.touch_gcal_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists gcal_touch_updated_at on public.google_calendar_connections;
create trigger gcal_touch_updated_at
  before update on public.google_calendar_connections
  for each row execute function public.touch_gcal_updated_at();
