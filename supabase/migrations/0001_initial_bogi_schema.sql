create extension if not exists vector;

create table public.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  created_at timestamptz not null default now()
);

create table public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  status text not null default 'active',
  created_at timestamptz not null default now()
);

create table public.planned_blocks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  calendar_event_id text,
  title text not null,
  start_time timestamptz not null,
  end_time timestamptz not null,
  intention_text text not null,
  success_criteria text not null,
  category text not null,
  created_by text not null check (created_by in ('user', 'planner_agent')),
  created_at timestamptz not null default now()
);

create table public.screen_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  planned_block_id uuid references public.planned_blocks(id) on delete set null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  capture_surface text not null default 'unknown',
  raw_frames_enabled boolean not null default false
);

create table public.screen_observation_summaries (
  id uuid primary key default gen_random_uuid(),
  planned_block_id uuid references public.planned_blocks(id) on delete cascade,
  screen_session_id uuid not null references public.screen_sessions(id) on delete cascade,
  time_window_start timestamptz not null,
  time_window_end timestamptz not null,
  observed_activities_json jsonb not null default '[]'::jsonb,
  confidence numeric not null default 0,
  raw_frames_stored_until timestamptz,
  created_at timestamptz not null default now()
);

create table public.screen_frame_batches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  planned_block_id uuid references public.planned_blocks(id) on delete set null,
  screen_session_id uuid references public.screen_sessions(id) on delete set null,
  frame_hash text not null,
  captured_at timestamptz not null,
  raw_frame_stored_until timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, frame_hash)
);

create table public.reality_logs (
  id uuid primary key default gen_random_uuid(),
  planned_block_id uuid references public.planned_blocks(id) on delete set null,
  user_id uuid not null references public.users(id) on delete cascade,
  actual_summary text not null,
  completion_score numeric not null check (completion_score >= 0 and completion_score <= 1),
  deviation_reason text not null default '',
  actual_categories_json jsonb not null default '[]'::jsonb,
  confirmed_by_user boolean not null default false,
  source text not null check (source in ('manual', 'screen_assisted', 'user_confirmed')),
  created_at timestamptz not null default now()
);

create table public.daily_summaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  day date not null,
  summary text not null,
  stats_json jsonb not null default '{}'::jsonb,
  unique (user_id, day)
);

create table public.weekly_summaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  week_start date not null,
  summary text not null,
  stats_json jsonb not null default '{}'::jsonb,
  unique (user_id, week_start)
);

create table public.monthly_summaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  month_start date not null,
  summary text not null,
  stats_json jsonb not null default '{}'::jsonb,
  unique (user_id, month_start)
);

create table public.user_patterns (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  pattern_key text not null,
  evidence_json jsonb not null default '{}'::jsonb,
  recommendation text not null,
  embedding vector(1536),
  updated_at timestamptz not null default now(),
  unique (user_id, pattern_key)
);

create table public.calendar_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  provider text not null check (provider = 'google'),
  access_token text not null,
  refresh_token text not null,
  sync_token text,
  channel_id text,
  resource_id text,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.agent_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,
  agent_name text not null,
  input_json jsonb not null default '{}'::jsonb,
  output_json jsonb not null default '{}'::jsonb,
  status text not null check (status in ('started', 'succeeded', 'failed')),
  created_at timestamptz not null default now()
);
