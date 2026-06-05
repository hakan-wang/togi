create extension if not exists "pgcrypto";

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text,
  status text not null default 'active' check (status in ('active', 'completed', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.planned_blocks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  calendar_event_id text,
  title text not null,
  start_time timestamptz not null,
  end_time timestamptz not null,
  intention_text text not null,
  success_criteria jsonb not null,
  category text not null,
  status text not null default 'planned' check (status in ('planned', 'completed', 'cancelled')),
  created_by text not null check (created_by in ('user', 'planner_agent')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(success_criteria) = 'array'),
  check (jsonb_array_length(success_criteria) > 0),
  check (lower(trim(intention_text)) not in ('be productive', 'work', 'focus', 'catch up', 'do stuff')),
  check (end_time > start_time)
);

create table if not exists public.reality_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  planned_block_id uuid not null references public.planned_blocks(id) on delete cascade,
  actual_summary text not null,
  completion_score numeric not null check (completion_score >= 0 and completion_score <= 1),
  deviation_reason text not null default '',
  actual_categories_json jsonb not null default '[]'::jsonb,
  confirmed_by_user boolean not null default true,
  source text not null check (source in ('user', 'reality_log_agent')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (confirmed_by_user = true)
);

create table if not exists public.calendar_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null default 'google' check (provider = 'google'),
  external_account_id text,
  access_token_encrypted text,
  refresh_token_encrypted text,
  sync_token text,
  connected_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.agent_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  agent_name text not null,
  input_json jsonb not null,
  output_json jsonb,
  status text not null check (status in ('started', 'completed', 'failed')),
  error text,
  model text not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.user_patterns (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  pattern_type text not null,
  evidence_json jsonb not null,
  recommendation text not null,
  confidence numeric not null check (confidence >= 0 and confidence <= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.goals enable row level security;
alter table public.users enable row level security;
alter table public.planned_blocks enable row level security;
alter table public.reality_logs enable row level security;
alter table public.calendar_connections enable row level security;
alter table public.agent_runs enable row level security;
alter table public.user_patterns enable row level security;

create policy "users owner access" on public.users for all using (auth.uid() = id) with check (auth.uid() = id);
create policy "goals owner access" on public.goals for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "planned_blocks owner access" on public.planned_blocks for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "reality_logs owner access" on public.reality_logs for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "calendar_connections owner access" on public.calendar_connections for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "agent_runs owner access" on public.agent_runs for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user_patterns owner access" on public.user_patterns for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger set_users_updated_at before update on public.users for each row execute function public.set_updated_at();
create trigger set_goals_updated_at before update on public.goals for each row execute function public.set_updated_at();
create trigger set_planned_blocks_updated_at before update on public.planned_blocks for each row execute function public.set_updated_at();
create trigger set_reality_logs_updated_at before update on public.reality_logs for each row execute function public.set_updated_at();
create trigger set_calendar_connections_updated_at before update on public.calendar_connections for each row execute function public.set_updated_at();
create trigger set_user_patterns_updated_at before update on public.user_patterns for each row execute function public.set_updated_at();
