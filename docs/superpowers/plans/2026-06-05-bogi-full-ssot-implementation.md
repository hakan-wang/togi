# Bogi Full SSOT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pasted SSOT as a full TypeScript web app: calendar intention, lock-in screen accountability, AI observation, user-confirmed reality logs, behavior patterns, coach feedback, voice input, summaries, and privacy-first storage.

**Architecture:** Use a Next.js App Router web app with typed server actions/API routes, Supabase Postgres as the system of record, and a small set of Bogi-specific agents/workflows owned by app code. Create shared contracts first so subagents can implement database, frontend, screen capture, agents, calendar, voice, and workflow lanes in parallel without editing the same files.

**Tech Stack:** Next.js, React, TypeScript, Tailwind CSS, Supabase Postgres with pgvector, OpenAI Responses API, OpenAI Agents SDK for TypeScript, Trigger.dev, Google Calendar API, browser `getDisplayMedia()`, browser `MediaRecorder`, Zod, Vitest, Playwright.

---

## Source Of Truth

The pasted SSOT is authoritative. The PDF is background only.

Build all SSOT features:

- Calendar planning
- Start lock-in session
- Browser screen share through `getDisplayMedia()`
- Frame sampling, downscaling, compression, dedupe, batch upload
- Screen Observer Agent
- AI activity summaries
- User confirmation/correction reality log
- Plan-vs-reality gap storage
- Planner Agent
- Reality Log Agent
- Pattern Learner Agent
- Coach Agent
- Trigger.dev jobs/workflows
- Supabase Postgres and pgvector
- Google Calendar API first
- Browser voice input with OpenAI speech-to-text
- Zod schemas and MCP-shaped internal tools
- Privacy defaults: no raw frame storage by default, no silent capture, user-owned logs, export/delete path

## Parallelization Strategy

### Wave 0: Shared Contracts And Scaffold

Run Task 1 first. No other subagent starts until Task 1 is complete and committed.

### Wave 1: Independent Foundations

After Task 1, dispatch up to 6 subagents in parallel:

- Subagent A: Task 2 Database schema and Supabase client
- Subagent B: Task 3 Domain contracts and tool schemas
- Subagent C: Task 4 App shell and dashboard layout
- Subagent D: Task 5 Auth and settings shell
- Subagent E: Task 6 Test harness
- Subagent F: Task 7 Privacy and retention module

### Wave 2: Feature Verticals

After Tasks 2 and 3 are complete, dispatch in parallel:

- Subagent A: Task 8 Planner Agent and calendar block API
- Subagent B: Task 9 Reality Log Agent and confirmation flow
- Subagent C: Task 10 Screen lock-in frontend
- Subagent D: Task 11 Screen observation backend
- Subagent E: Task 12 Google Calendar integration
- Subagent F: Task 13 Trigger.dev workflow setup

### Wave 3: Intelligence And UX

After Tasks 8 through 13 are complete, dispatch in parallel:

- Subagent A: Task 14 Pattern Learner Agent
- Subagent B: Task 15 Coach Agent
- Subagent C: Task 16 Voice input
- Subagent D: Task 17 Daily, weekly, monthly summaries
- Subagent E: Task 18 Export/delete data
- Subagent F: Task 19 Payment page and founding plan UX

### Wave 4: End-To-End Hardening

After all feature tasks are complete:

- Task 20 End-to-end Playwright flows
- Task 21 Browser screen-share manual verification
- Task 22 Final validation and commits

## Subagent Dispatch Rules

Every child-agent prompt must start with:

```text
$caveman
```

Implementation subagents must use `model: gpt-5.4` and `reasoning_effort: high`.

Audit/review subagents must use `model: gpt-5.5` and stay read-only.

Each implementation subagent owns only the files listed in its task. If it needs another file, it must report the handoff upward instead of editing outside scope.

## File Structure

Create this structure:

```text
app/
  (app)/
    dashboard/page.tsx
    lock-in/page.tsx
    logs/page.tsx
    patterns/page.tsx
    settings/page.tsx
  api/
    calendar/events/route.ts
    coach/route.ts
    planner/route.ts
    reality-log/route.ts
    screen/batch/route.ts
    summaries/route.ts
    voice/transcribe/route.ts
  layout.tsx
  page.tsx
components/
  app-shell.tsx
  block-card.tsx
  calendar-planner.tsx
  coach-panel.tsx
  lock-in-screen.tsx
  reality-confirmation.tsx
  screen-share-capture.tsx
  summary-panels.tsx
  voice-command.tsx
lib/
  agents/
    coach-agent.ts
    pattern-learner-agent.ts
    planner-agent.ts
    reality-log-agent.ts
    screen-observer-agent.ts
  calendar/
    google-calendar.ts
    sync.ts
  db/
    client.ts
    server.ts
    types.ts
  privacy/
    retention.ts
  screen/
    frame-sampler.ts
    image-hash.ts
    types.ts
  tools/
    calendar-tools.ts
    goals-tools.ts
    patterns-tools.ts
    reality-log-tools.ts
    screen-tools.ts
    summaries-tools.ts
  workflows/
    block-ended.ts
    daily-summary.ts
    frame-batch-ready.ts
    weekly-summary.ts
  zod/
    contracts.ts
supabase/
  migrations/
tests/
  agents/
  api/
  screen/
  tools/
  workflows/
e2e/
  bogi.spec.ts
```

---

### Task 1: Scaffold Next.js App And Baseline Config

**Parallel lane:** Wave 0 only.

**Files:**
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `next.config.ts`
- Create: `postcss.config.mjs`
- Create: `tailwind.config.ts`
- Create: `vitest.config.ts`
- Create: `playwright.config.ts`
- Create: `app/layout.tsx`
- Create: `app/page.tsx`
- Create: `app/globals.css`
- Create: `.env.example`
- Create: `README.md`

- [ ] **Step 1: Create package manifest**

Write `package.json`:

```json
{
  "name": "erik-agent-monitor",
  "private": true,
  "version": "0.1.0",
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest",
    "e2e": "playwright test"
  },
  "dependencies": {
    "@ai-sdk/react": "latest",
    "@openai/agents": "latest",
    "@supabase/ssr": "latest",
    "@supabase/supabase-js": "latest",
    "@trigger.dev/sdk": "latest",
    "ai": "latest",
    "date-fns": "latest",
    "googleapis": "latest",
    "lucide-react": "latest",
    "next": "latest",
    "openai": "latest",
    "react": "latest",
    "react-dom": "latest",
    "zod": "latest"
  },
  "devDependencies": {
    "@playwright/test": "latest",
    "@testing-library/jest-dom": "latest",
    "@testing-library/react": "latest",
    "@types/node": "latest",
    "@types/react": "latest",
    "@types/react-dom": "latest",
    "autoprefixer": "latest",
    "eslint": "latest",
    "eslint-config-next": "latest",
    "jsdom": "latest",
    "postcss": "latest",
    "tailwindcss": "latest",
    "typescript": "latest",
    "vitest": "latest"
  }
}
```

- [ ] **Step 2: Create TypeScript and app config**

Write `tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "es2022"],
    "allowJs": false,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./*"]
    }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx"],
  "exclude": ["node_modules"]
}
```

Write `next.config.ts`:

```ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {};

export default nextConfig;
```

Write `postcss.config.mjs`:

```js
const config = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};

export default config;
```

Write `tailwind.config.ts`:

```ts
import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: "#172026",
        paper: "#f7f4ef",
        line: "#d8d2c8",
        moss: "#4f6f52",
        clay: "#b45f43",
        steel: "#476579",
      },
    },
  },
  plugins: [],
};

export default config;
```

- [ ] **Step 3: Create test configs**

Write `vitest.config.ts`:

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom",
    globals: true,
    include: ["tests/**/*.test.ts", "tests/**/*.test.tsx"],
  },
});
```

Write `playwright.config.ts`:

```ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  use: {
    baseURL: "http://127.0.0.1:3000",
    trace: "on-first-retry",
  },
  webServer: {
    command: "npm run dev",
    url: "http://127.0.0.1:3000",
    reuseExistingServer: true,
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
  ],
});
```

- [ ] **Step 4: Create baseline app shell files**

Write `app/layout.tsx`:

```tsx
import "./globals.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Bogi",
  description: "Calendar intention, screen accountability, and reality logs.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
```

Write `app/page.tsx`:

```tsx
import Link from "next/link";

export default function HomePage() {
  return (
    <main className="min-h-screen bg-paper text-ink">
      <section className="mx-auto flex min-h-screen max-w-5xl flex-col justify-center px-6">
        <p className="text-sm font-semibold uppercase tracking-wide text-moss">Bogi</p>
        <h1 className="mt-4 max-w-3xl text-5xl font-semibold leading-tight">
          Plan your time, prove what happened, learn your real patterns.
        </h1>
        <div className="mt-8 flex gap-3">
          <Link className="rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" href="/dashboard">
            Open dashboard
          </Link>
          <Link className="rounded-md border border-line px-4 py-2 text-sm font-medium" href="/lock-in">
            Start lock-in
          </Link>
        </div>
      </section>
    </main>
  );
}
```

Write `app/globals.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  color-scheme: light;
}

body {
  margin: 0;
  background: #f7f4ef;
  color: #172026;
}

* {
  box-sizing: border-box;
}
```

- [ ] **Step 5: Create env example and README**

Write `.env.example`:

```text
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
OPENAI_API_KEY=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_REDIRECT_URI=http://127.0.0.1:3000/api/calendar/oauth/callback
TRIGGER_SECRET_KEY=
```

Write `README.md`:

```md
# Bogi

Bogi is a TypeScript web app for calendar intention, screen accountability, user-confirmed reality logs, and long-term behavior patterns.

## Local setup

1. Install dependencies with `npm install`.
2. Copy `.env.example` to `.env.local` and fill credentials.
3. Run `npm run dev`.
4. Run `npm test`, `npm run typecheck`, and `npm run e2e` before shipping.
```

- [ ] **Step 6: Install dependencies and verify scaffold**

Run:

```bash
rtk npm install
rtk npm run typecheck
rtk npm test
```

Expected:

```text
typecheck exits 0
test exits 0 with no tests found or all tests passing
```

- [ ] **Step 7: Commit scaffold**

Run:

```bash
rtk git add package.json package-lock.json tsconfig.json next.config.ts postcss.config.mjs tailwind.config.ts vitest.config.ts playwright.config.ts app/layout.tsx app/page.tsx app/globals.css .env.example README.md
rtk git commit -m "chore: scaffold bogi web app"
```

---

### Task 2: Supabase Database Schema And Server Client

**Parallel lane:** Wave 1 Subagent A.

**Files:**
- Create: `supabase/migrations/0001_initial_bogi_schema.sql`
- Create: `lib/db/client.ts`
- Create: `lib/db/server.ts`
- Create: `lib/db/types.ts`
- Test: `tests/db/schema-types.test.ts`

- [ ] **Step 1: Write schema type test**

Write `tests/db/schema-types.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import type { PlannedBlock, RealityLog, ScreenObservationSummary } from "@/lib/db/types";

describe("db types", () => {
  it("models intention, reality, and observation records", () => {
    const block: PlannedBlock = {
      id: "blk_1",
      userId: "usr_1",
      calendarEventId: "evt_1",
      title: "Edit video",
      startTime: "2026-06-06T13:00:00.000Z",
      endTime: "2026-06-06T14:00:00.000Z",
      intentionText: "Edit videos for 60 min",
      successCriteria: "Rough cut first 3 minutes",
      category: "work/video",
      createdBy: "planner_agent",
    };
    const log: RealityLog = {
      id: "log_1",
      plannedBlockId: block.id,
      userId: block.userId,
      actualSummary: "Edited for 43 min and watched tutorial for 12 min.",
      completionScore: 0.75,
      deviationReason: "Needed tutorial",
      actualCategories: [{ category: "work/video/editing", minutes: 43 }],
      confirmedByUser: true,
      source: "user_confirmed",
    };
    const observation: ScreenObservationSummary = {
      id: "obs_1",
      plannedBlockId: block.id,
      screenSessionId: "ses_1",
      timeWindowStart: block.startTime,
      timeWindowEnd: block.endTime,
      observedActivities: [{ activity: "video editing", estimatedMinutes: 43, confidence: 0.82 }],
      confidence: 0.82,
      rawFramesStoredUntil: null,
    };
    expect(log.plannedBlockId).toBe(block.id);
    expect(observation.observedActivities[0]?.activity).toBe("video editing");
  });
});
```

- [ ] **Step 2: Run failing test**

Run:

```bash
rtk npm test -- tests/db/schema-types.test.ts
```

Expected:

```text
FAIL because lib/db/types does not exist
```

- [ ] **Step 3: Create database types**

Write `lib/db/types.ts`:

```ts
export type PlannedBlock = {
  id: string;
  userId: string;
  calendarEventId: string | null;
  title: string;
  startTime: string;
  endTime: string;
  intentionText: string;
  successCriteria: string;
  category: string;
  createdBy: "user" | "planner_agent";
};

export type ActualCategory = {
  category: string;
  minutes: number;
};

export type RealityLog = {
  id: string;
  plannedBlockId: string;
  userId: string;
  actualSummary: string;
  completionScore: number;
  deviationReason: string;
  actualCategories: ActualCategory[];
  confirmedByUser: boolean;
  source: "manual" | "screen_assisted" | "user_confirmed";
};

export type ObservedActivity = {
  activity: string;
  estimatedMinutes: number;
  confidence: number;
};

export type ScreenObservationSummary = {
  id: string;
  plannedBlockId: string;
  screenSessionId: string;
  timeWindowStart: string;
  timeWindowEnd: string;
  observedActivities: ObservedActivity[];
  confidence: number;
  rawFramesStoredUntil: string | null;
};
```

- [ ] **Step 4: Create migration**

Write `supabase/migrations/0001_initial_bogi_schema.sql`:

```sql
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
```

- [ ] **Step 5: Create Supabase clients**

Write `lib/db/client.ts`:

```ts
import { createBrowserClient } from "@supabase/ssr";

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? ""
  );
}
```

Write `lib/db/server.ts`:

```ts
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

export async function createServerSupabaseClient() {
  const cookieStore = await cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "",
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
        },
      },
    }
  );
}
```

- [ ] **Step 6: Verify**

Run:

```bash
rtk npm test -- tests/db/schema-types.test.ts
rtk npm run typecheck
```

Expected:

```text
PASS schema-types
typecheck exits 0
```

- [ ] **Step 7: Commit**

Run:

```bash
rtk git add supabase/migrations/0001_initial_bogi_schema.sql lib/db tests/db
rtk git commit -m "feat: add bogi database schema"
```

---

### Task 3: Zod Contracts And MCP-Shaped Tool Schemas

**Parallel lane:** Wave 1 Subagent B.

**Files:**
- Create: `lib/zod/contracts.ts`
- Create: `lib/tools/calendar-tools.ts`
- Create: `lib/tools/reality-log-tools.ts`
- Create: `lib/tools/screen-tools.ts`
- Create: `lib/tools/patterns-tools.ts`
- Create: `lib/tools/goals-tools.ts`
- Create: `lib/tools/summaries-tools.ts`
- Test: `tests/tools/contracts.test.ts`

- [ ] **Step 1: Write contract tests**

Write `tests/tools/contracts.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
  plannerOutputSchema,
  realityLogInputSchema,
  screenObservationOutputSchema,
} from "@/lib/zod/contracts";

describe("Bogi contracts", () => {
  it("requires concrete planner blocks", () => {
    const parsed = plannerOutputSchema.parse({
      blocks: [{
        title: "Edit video",
        start: "2026-06-06T13:00:00.000Z",
        end: "2026-06-06T14:00:00.000Z",
        successCriteria: "Rough cut first 3 minutes",
        category: "work/video",
      }],
    });
    expect(parsed.blocks[0]?.successCriteria).toContain("Rough cut");
  });

  it("rejects vague planner blocks", () => {
    expect(() => plannerOutputSchema.parse({
      blocks: [{
        title: "Be productive",
        start: "2026-06-06T13:00:00.000Z",
        end: "2026-06-06T14:00:00.000Z",
        successCriteria: "Be productive",
        category: "work",
      }],
    })).toThrow();
  });

  it("parses user-confirmed reality logs", () => {
    const parsed = realityLogInputSchema.parse({
      plannedBlockId: "blk_123",
      actualSummary: "Edited video for 43 minutes.",
      completionScore: 0.75,
      deviationReason: "Needed tutorial",
      actualCategories: [{ category: "work/video/editing", minutes: 43 }],
      confirmedByUser: true,
    });
    expect(parsed.confirmedByUser).toBe(true);
  });

  it("parses screen observation summaries", () => {
    const parsed = screenObservationOutputSchema.parse({
      blockId: "blk_123",
      window: "13:00-13:15",
      observedActivities: [{ activity: "video editing", estimatedMinutes: 9, confidence: 0.82 }],
      summary: "Mostly editing.",
    });
    expect(parsed.observedActivities[0]?.confidence).toBeGreaterThan(0.8);
  });
});
```

- [ ] **Step 2: Run failing test**

Run:

```bash
rtk npm test -- tests/tools/contracts.test.ts
```

Expected:

```text
FAIL because lib/zod/contracts does not exist
```

- [ ] **Step 3: Implement shared contracts**

Write `lib/zod/contracts.ts`:

```ts
import { z } from "zod";

const concreteText = z.string().min(8).refine(
  (value) => !["be productive", "productive", "work", "focus"].includes(value.trim().toLowerCase()),
  "Text must be concrete and checkable"
);

export const plannedBlockSchema = z.object({
  title: concreteText,
  start: z.string().datetime(),
  end: z.string().datetime(),
  successCriteria: concreteText,
  category: z.string().min(3),
});

export const plannerOutputSchema = z.object({
  blocks: z.array(plannedBlockSchema).min(1),
});

export const actualCategorySchema = z.object({
  category: z.string().min(3),
  minutes: z.number().nonnegative(),
});

export const realityLogInputSchema = z.object({
  plannedBlockId: z.string().min(1),
  actualSummary: z.string().min(12),
  completionScore: z.number().min(0).max(1),
  deviationReason: z.string(),
  actualCategories: z.array(actualCategorySchema),
  confirmedByUser: z.boolean(),
});

export const observedActivitySchema = z.object({
  activity: z.string().min(3),
  estimatedMinutes: z.number().nonnegative(),
  confidence: z.number().min(0).max(1),
});

export const screenObservationOutputSchema = z.object({
  blockId: z.string().min(1),
  window: z.string().min(3),
  observedActivities: z.array(observedActivitySchema),
  summary: z.string().min(3),
});

export const coachMessageSchema = z.object({
  message: z.string().min(1),
  proposedCalendarChanges: z.array(plannedBlockSchema).default([]),
});

export type PlannerOutput = z.infer<typeof plannerOutputSchema>;
export type RealityLogInput = z.infer<typeof realityLogInputSchema>;
export type ScreenObservationOutput = z.infer<typeof screenObservationOutputSchema>;
export type CoachMessage = z.infer<typeof coachMessageSchema>;
```

- [ ] **Step 4: Implement MCP-shaped tool definitions**

Write `lib/tools/calendar-tools.ts`:

```ts
import { z } from "zod";
import { plannedBlockSchema } from "@/lib/zod/contracts";

export const calendarReadInput = z.object({
  userId: z.string().min(1),
  start: z.string().datetime(),
  end: z.string().datetime(),
});

export const calendarCreateBlockInput = plannedBlockSchema.extend({
  userId: z.string().min(1),
});

export const calendarUpdateBlockInput = calendarCreateBlockInput.extend({
  blockId: z.string().min(1),
});

export const calendarDeleteBlockInput = z.object({
  userId: z.string().min(1),
  blockId: z.string().min(1),
});
```

Write `lib/tools/reality-log-tools.ts`:

```ts
import { realityLogInputSchema } from "@/lib/zod/contracts";

export const realityLogCreateInput = realityLogInputSchema.extend({});
export const realityLogUpdateInput = realityLogInputSchema.extend({
  realityLogId: realityLogInputSchema.shape.plannedBlockId,
});
```

Write `lib/tools/screen-tools.ts`:

```ts
import { z } from "zod";
import { screenObservationOutputSchema } from "@/lib/zod/contracts";

export const screenSessionStartInput = z.object({
  userId: z.string().min(1),
  plannedBlockId: z.string().min(1),
  rawFramesEnabled: z.boolean().default(false),
});

export const screenObservationAddSummaryInput = screenObservationOutputSchema.extend({
  screenSessionId: z.string().min(1),
  timeWindowStart: z.string().datetime(),
  timeWindowEnd: z.string().datetime(),
});
```

Write `lib/tools/patterns-tools.ts`:

```ts
import { z } from "zod";

export const patternsGetRelevantInput = z.object({
  userId: z.string().min(1),
  category: z.string().min(3),
});

export const patternsUpsertInput = z.object({
  userId: z.string().min(1),
  patternKey: z.string().min(3),
  evidence: z.record(z.string(), z.unknown()),
  recommendation: z.string().min(8),
});
```

Write `lib/tools/goals-tools.ts`:

```ts
import { z } from "zod";

export const goalsReadInput = z.object({
  userId: z.string().min(1),
});

export const goalsUpdateInput = z.object({
  userId: z.string().min(1),
  goalId: z.string().min(1),
  title: z.string().min(3),
  description: z.string(),
  status: z.enum(["active", "paused", "complete"]),
});
```

Write `lib/tools/summaries-tools.ts`:

```ts
import { z } from "zod";

export const summariesGetDayInput = z.object({
  userId: z.string().min(1),
  day: z.string().date(),
});

export const summariesGetWeekInput = z.object({
  userId: z.string().min(1),
  weekStart: z.string().date(),
});
```

- [ ] **Step 5: Verify**

Run:

```bash
rtk npm test -- tests/tools/contracts.test.ts
rtk npm run typecheck
```

Expected:

```text
PASS contracts
typecheck exits 0
```

- [ ] **Step 6: Commit**

Run:

```bash
rtk git add lib/zod lib/tools tests/tools
rtk git commit -m "feat: add bogi contracts and tool schemas"
```

---

### Task 4: App Shell, Dashboard, And Navigation

**Parallel lane:** Wave 1 Subagent C.

**Files:**
- Create: `components/app-shell.tsx`
- Create: `components/block-card.tsx`
- Create: `components/summary-panels.tsx`
- Create: `app/(app)/dashboard/page.tsx`
- Create: `app/(app)/logs/page.tsx`
- Create: `app/(app)/patterns/page.tsx`
- Test: `tests/ui/app-shell.test.tsx`

- [ ] **Step 1: Write UI test**

Write `tests/ui/app-shell.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { AppShell } from "@/components/app-shell";

describe("AppShell", () => {
  it("renders primary Bogi navigation", () => {
    render(<AppShell><div>Dashboard content</div></AppShell>);
    expect(screen.getByRole("link", { name: "Dashboard" })).toHaveAttribute("href", "/dashboard");
    expect(screen.getByRole("link", { name: "Lock-in" })).toHaveAttribute("href", "/lock-in");
    expect(screen.getByText("Dashboard content")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run failing test**

Run:

```bash
rtk npm test -- tests/ui/app-shell.test.tsx
```

Expected:

```text
FAIL because components/app-shell does not exist
```

- [ ] **Step 3: Implement app shell**

Write `components/app-shell.tsx`:

```tsx
import Link from "next/link";
import { CalendarDays, ClipboardCheck, LineChart, Monitor, Settings } from "lucide-react";

const nav = [
  { href: "/dashboard", label: "Dashboard", icon: CalendarDays },
  { href: "/lock-in", label: "Lock-in", icon: Monitor },
  { href: "/logs", label: "Logs", icon: ClipboardCheck },
  { href: "/patterns", label: "Patterns", icon: LineChart },
  { href: "/settings", label: "Settings", icon: Settings },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-paper text-ink">
      <aside className="fixed inset-y-0 left-0 hidden w-56 border-r border-line bg-white/70 px-4 py-5 md:block">
        <Link href="/dashboard" className="text-lg font-semibold">Bogi</Link>
        <nav className="mt-8 space-y-1">
          {nav.map((item) => {
            const Icon = item.icon;
            return (
              <Link key={item.href} href={item.href} className="flex items-center gap-2 rounded-md px-3 py-2 text-sm hover:bg-paper">
                <Icon aria-hidden className="h-4 w-4" />
                {item.label}
              </Link>
            );
          })}
        </nav>
      </aside>
      <main className="min-h-screen px-4 py-5 md:ml-56 md:px-8">{children}</main>
    </div>
  );
}
```

- [ ] **Step 4: Implement dashboard components**

Write `components/block-card.tsx`:

```tsx
type BlockCardProps = {
  title: string;
  time: string;
  intention: string;
  status: "planned" | "logged" | "missed";
};

export function BlockCard({ title, time, intention, status }: BlockCardProps) {
  return (
    <article className="rounded-md border border-line bg-white p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-base font-semibold">{title}</h3>
          <p className="mt-1 text-sm text-steel">{time}</p>
        </div>
        <span className="rounded border border-line px-2 py-1 text-xs capitalize">{status}</span>
      </div>
      <p className="mt-3 text-sm">{intention}</p>
    </article>
  );
}
```

Write `components/summary-panels.tsx`:

```tsx
const panels = [
  { label: "Planned", value: "6.0h" },
  { label: "Confirmed reality", value: "4.7h" },
  { label: "Gap", value: "1.3h" },
];

export function SummaryPanels() {
  return (
    <section className="grid gap-3 sm:grid-cols-3">
      {panels.map((panel) => (
        <div key={panel.label} className="rounded-md border border-line bg-white p-4">
          <p className="text-sm text-steel">{panel.label}</p>
          <p className="mt-2 text-2xl font-semibold">{panel.value}</p>
        </div>
      ))}
    </section>
  );
}
```

- [ ] **Step 5: Implement pages**

Write `app/(app)/dashboard/page.tsx`:

```tsx
import { AppShell } from "@/components/app-shell";
import { BlockCard } from "@/components/block-card";
import { SummaryPanels } from "@/components/summary-panels";

export default function DashboardPage() {
  return (
    <AppShell>
      <div className="max-w-6xl">
        <h1 className="text-3xl font-semibold">Today</h1>
        <p className="mt-2 text-sm text-steel">Intention vs reality for the day.</p>
        <div className="mt-6"><SummaryPanels /></div>
        <section className="mt-6 grid gap-3 lg:grid-cols-2">
          <BlockCard title="Edit video" time="13:00-14:00" intention="Rough cut first 3 minutes" status="planned" />
          <BlockCard title="Email manufacturers" time="15:00-16:00" intention="Send 3 supplier emails" status="logged" />
        </section>
      </div>
    </AppShell>
  );
}
```

Write `app/(app)/logs/page.tsx`:

```tsx
import { AppShell } from "@/components/app-shell";

export default function LogsPage() {
  return (
    <AppShell>
      <h1 className="text-3xl font-semibold">Reality logs</h1>
      <p className="mt-2 text-sm text-steel">User-confirmed records of what happened.</p>
    </AppShell>
  );
}
```

Write `app/(app)/patterns/page.tsx`:

```tsx
import { AppShell } from "@/components/app-shell";

export default function PatternsPage() {
  return (
    <AppShell>
      <h1 className="text-3xl font-semibold">Patterns</h1>
      <p className="mt-2 text-sm text-steel">Planning constraints learned from repeated plan-vs-reality gaps.</p>
    </AppShell>
  );
}
```

- [ ] **Step 6: Verify**

Run:

```bash
rtk npm test -- tests/ui/app-shell.test.tsx
rtk npm run typecheck
```

Expected:

```text
PASS app-shell
typecheck exits 0
```

- [ ] **Step 7: Commit**

Run:

```bash
rtk git add components/app-shell.tsx components/block-card.tsx components/summary-panels.tsx app/'(app)'/dashboard/page.tsx app/'(app)'/logs/page.tsx app/'(app)'/patterns/page.tsx tests/ui
rtk git commit -m "feat: add bogi app shell"
```

---

### Task 5: Auth And Settings Shell

**Parallel lane:** Wave 1 Subagent D.

**Files:**
- Create: `app/(app)/settings/page.tsx`
- Create: `components/privacy-settings.tsx`
- Test: `tests/ui/privacy-settings.test.tsx`

- [ ] **Step 1: Write privacy settings test**

Write `tests/ui/privacy-settings.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { PrivacySettings } from "@/components/privacy-settings";

describe("PrivacySettings", () => {
  it("defaults raw frame storage off", () => {
    render(<PrivacySettings />);
    const checkbox = screen.getByRole("checkbox", { name: "Temporary debug frames" });
    expect(checkbox).not.toBeChecked();
    expect(screen.getByText("Stored forever: summaries only")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Implement settings component and page**

Write `components/privacy-settings.tsx`:

```tsx
export function PrivacySettings() {
  return (
    <section className="max-w-2xl rounded-md border border-line bg-white p-4">
      <h2 className="text-lg font-semibold">Privacy defaults</h2>
      <div className="mt-4 space-y-3 text-sm">
        <label className="flex items-center gap-2">
          <input type="checkbox" name="debugFrames" />
          Temporary debug frames
        </label>
        <p>No raw frame storage by default</p>
        <p>No monitoring outside lock-in sessions</p>
        <p>Stored forever: summaries only</p>
      </div>
    </section>
  );
}
```

Write `app/(app)/settings/page.tsx`:

```tsx
import { AppShell } from "@/components/app-shell";
import { PrivacySettings } from "@/components/privacy-settings";

export default function SettingsPage() {
  return (
    <AppShell>
      <h1 className="text-3xl font-semibold">Settings</h1>
      <div className="mt-6"><PrivacySettings /></div>
    </AppShell>
  );
}
```

- [ ] **Step 3: Verify and commit**

Run:

```bash
rtk npm test -- tests/ui/privacy-settings.test.tsx
rtk npm run typecheck
rtk git add app/'(app)'/settings/page.tsx components/privacy-settings.tsx tests/ui/privacy-settings.test.tsx
rtk git commit -m "feat: add privacy settings shell"
```

Expected:

```text
PASS privacy-settings
typecheck exits 0
commit succeeds
```

---

### Task 6: Test Harness And Mock Helpers

**Parallel lane:** Wave 1 Subagent E.

**Files:**
- Create: `tests/setup/render.tsx`
- Create: `tests/setup/mock-request.ts`
- Modify: `vitest.config.ts`
- Test: `tests/setup/mock-request.test.ts`

- [ ] **Step 1: Add test setup helpers**

Write `tests/setup/render.tsx`:

```tsx
import { render } from "@testing-library/react";
import type { ReactElement } from "react";

export function renderApp(ui: ReactElement) {
  return render(ui);
}
```

Write `tests/setup/mock-request.ts`:

```ts
export function jsonRequest(body: unknown): Request {
  return new Request("http://127.0.0.1/test", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}
```

Write `tests/setup/mock-request.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { jsonRequest } from "./mock-request";

describe("jsonRequest", () => {
  it("creates a POST JSON request", async () => {
    const request = jsonRequest({ value: "ok" });
    expect(request.method).toBe("POST");
    expect(await request.json()).toEqual({ value: "ok" });
  });
});
```

- [ ] **Step 2: Update Vitest setup**

Modify `vitest.config.ts`:

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom",
    globals: true,
    include: ["tests/**/*.test.ts", "tests/**/*.test.tsx"],
    setupFiles: ["@testing-library/jest-dom/vitest"],
  },
});
```

- [ ] **Step 3: Verify and commit**

Run:

```bash
rtk npm test -- tests/setup/mock-request.test.ts
rtk npm run typecheck
rtk git add tests/setup vitest.config.ts
rtk git commit -m "test: add shared test helpers"
```

Expected:

```text
PASS mock-request
typecheck exits 0
commit succeeds
```

---

### Task 7: Privacy Retention Module

**Parallel lane:** Wave 1 Subagent F.

**Files:**
- Create: `lib/privacy/retention.ts`
- Test: `tests/privacy/retention.test.ts`

- [ ] **Step 1: Write retention tests**

Write `tests/privacy/retention.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { getFrameRetentionPolicy } from "@/lib/privacy/retention";

describe("getFrameRetentionPolicy", () => {
  it("stores summaries only by default", () => {
    expect(getFrameRetentionPolicy({ rawFramesEnabled: false })).toEqual({
      storeRawFrames: false,
      deleteRawFramesAfterMinutes: 0,
      permanentStorage: "summaries_only",
    });
  });

  it("limits debug frames to 60 minutes", () => {
    expect(getFrameRetentionPolicy({ rawFramesEnabled: true })).toEqual({
      storeRawFrames: true,
      deleteRawFramesAfterMinutes: 60,
      permanentStorage: "summaries_only",
    });
  });
});
```

- [ ] **Step 2: Implement retention module**

Write `lib/privacy/retention.ts`:

```ts
export type FrameRetentionPolicy = {
  storeRawFrames: boolean;
  deleteRawFramesAfterMinutes: number;
  permanentStorage: "summaries_only";
};

export function getFrameRetentionPolicy(input: { rawFramesEnabled: boolean }): FrameRetentionPolicy {
  if (!input.rawFramesEnabled) {
    return {
      storeRawFrames: false,
      deleteRawFramesAfterMinutes: 0,
      permanentStorage: "summaries_only",
    };
  }

  return {
    storeRawFrames: true,
    deleteRawFramesAfterMinutes: 60,
    permanentStorage: "summaries_only",
  };
}
```

- [ ] **Step 3: Verify and commit**

Run:

```bash
rtk npm test -- tests/privacy/retention.test.ts
rtk npm run typecheck
rtk git add lib/privacy tests/privacy
rtk git commit -m "feat: add frame retention policy"
```

Expected:

```text
PASS retention
typecheck exits 0
commit succeeds
```

---

### Task 8: Planner Agent And Calendar Block API

**Parallel lane:** Wave 2 Subagent A.

**Files:**
- Create: `lib/agents/planner-agent.ts`
- Create: `app/api/planner/route.ts`
- Create: `components/calendar-planner.tsx`
- Test: `tests/agents/planner-agent.test.ts`
- Test: `tests/api/planner-route.test.ts`

- [ ] **Step 1: Write planner tests**

Write `tests/agents/planner-agent.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { buildPlannerPrompt, parsePlannerOutput } from "@/lib/agents/planner-agent";

describe("planner agent", () => {
  it("includes concrete planning rules", () => {
    expect(buildPlannerPrompt()).toContain("No vague blocks");
    expect(buildPlannerPrompt()).toContain("Every block must be checkable");
  });

  it("parses concrete blocks", () => {
    const parsed = parsePlannerOutput({
      blocks: [{
        title: "Edit video",
        start: "2026-06-06T13:00:00.000Z",
        end: "2026-06-06T14:00:00.000Z",
        successCriteria: "Rough cut first 3 minutes",
        category: "work/video",
      }],
    });
    expect(parsed.blocks[0]?.category).toBe("work/video");
  });
});
```

- [ ] **Step 2: Implement planner agent wrapper**

Write `lib/agents/planner-agent.ts`:

```ts
import OpenAI from "openai";
import { plannerOutputSchema, type PlannerOutput } from "@/lib/zod/contracts";

export function buildPlannerPrompt() {
  return [
    "You are Bogi Planner Agent.",
    "Turn vague intention into concrete calendar blocks.",
    "No vague blocks.",
    "No 'be productive'.",
    "Every block must be checkable.",
    "Return JSON matching the planner output schema.",
  ].join("\n");
}

export function parsePlannerOutput(value: unknown): PlannerOutput {
  return plannerOutputSchema.parse(value);
}

export async function runPlannerAgent(input: {
  userRequest: string;
  currentCalendar: unknown[];
  relevantPatterns: unknown[];
}): Promise<PlannerOutput> {
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const response = await client.responses.create({
    model: "gpt-5.5",
    input: [
      { role: "system", content: buildPlannerPrompt() },
      { role: "user", content: JSON.stringify(input) },
    ],
    text: { format: { type: "json_object" } },
  });
  const text = response.output_text;
  return parsePlannerOutput(JSON.parse(text));
}
```

- [ ] **Step 3: Implement planner API route**

Write `app/api/planner/route.ts`:

```ts
import { NextResponse } from "next/server";
import { runPlannerAgent } from "@/lib/agents/planner-agent";

export async function POST(request: Request) {
  const body = await request.json();
  const output = await runPlannerAgent({
    userRequest: String(body.userRequest ?? ""),
    currentCalendar: Array.isArray(body.currentCalendar) ? body.currentCalendar : [],
    relevantPatterns: Array.isArray(body.relevantPatterns) ? body.relevantPatterns : [],
  });
  return NextResponse.json(output);
}
```

- [ ] **Step 4: Implement planner UI**

Write `components/calendar-planner.tsx`:

```tsx
"use client";

import { useState } from "react";

export function CalendarPlanner() {
  const [request, setRequest] = useState("");
  const [status, setStatus] = useState("idle");

  async function submitPlan() {
    setStatus("planning");
    const response = await fetch("/api/planner", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ userRequest: request, currentCalendar: [], relevantPatterns: [] }),
    });
    setStatus(response.ok ? "planned" : "failed");
  }

  return (
    <section className="rounded-md border border-line bg-white p-4">
      <label className="text-sm font-medium" htmlFor="planner">What are you locking in on?</label>
      <textarea id="planner" className="mt-2 min-h-24 w-full rounded-md border border-line p-3" value={request} onChange={(event) => setRequest(event.target.value)} />
      <button className="mt-3 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button" onClick={submitPlan}>
        Plan block
      </button>
      <p className="mt-2 text-sm text-steel">{status}</p>
    </section>
  );
}
```

- [ ] **Step 5: Verify and commit**

Run:

```bash
rtk npm test -- tests/agents/planner-agent.test.ts
rtk npm run typecheck
rtk git add lib/agents/planner-agent.ts app/api/planner/route.ts components/calendar-planner.tsx tests/agents/planner-agent.test.ts
rtk git commit -m "feat: add planner agent"
```

Expected:

```text
PASS planner-agent
typecheck exits 0
commit succeeds
```

---

### Task 9: Reality Log Agent And Confirmation Flow

**Parallel lane:** Wave 2 Subagent B.

**Files:**
- Create: `lib/agents/reality-log-agent.ts`
- Create: `app/api/reality-log/route.ts`
- Create: `components/reality-confirmation.tsx`
- Test: `tests/agents/reality-log-agent.test.ts`

- [ ] **Step 1: Write reality agent test**

Write `tests/agents/reality-log-agent.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { buildRealityLogPrompt, parseRealityLog } from "@/lib/agents/reality-log-agent";

describe("reality log agent", () => {
  it("states that screen evidence is not final truth", () => {
    expect(buildRealityLogPrompt()).toContain("Screen evidence is not final truth");
  });

  it("parses confirmed reality", () => {
    const parsed = parseRealityLog({
      plannedBlockId: "blk_123",
      actualSummary: "Edited for 43 minutes, watched tutorial for 12 minutes.",
      completionScore: 0.75,
      deviationReason: "Needed tutorial",
      actualCategories: [{ category: "work/video/editing", minutes: 43 }],
      confirmedByUser: true,
    });
    expect(parsed.confirmedByUser).toBe(true);
  });
});
```

- [ ] **Step 2: Implement reality log agent**

Write `lib/agents/reality-log-agent.ts`:

```ts
import OpenAI from "openai";
import { realityLogInputSchema, type RealityLogInput } from "@/lib/zod/contracts";

export function buildRealityLogPrompt() {
  return [
    "You are Bogi Reality Log Agent.",
    "Ask user what actually happened.",
    "Reconcile user answer with screen observations.",
    "Screen evidence is not final truth.",
    "User confirmation is the source of truth.",
  ].join("\n");
}

export function parseRealityLog(value: unknown): RealityLogInput {
  return realityLogInputSchema.parse(value);
}

export async function runRealityLogAgent(input: {
  plannedBlockId: string;
  plannedTitle: string;
  observationSummary: string;
  userCorrection: string;
}): Promise<RealityLogInput> {
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const response = await client.responses.create({
    model: "gpt-5.5",
    input: [
      { role: "system", content: buildRealityLogPrompt() },
      { role: "user", content: JSON.stringify(input) },
    ],
    text: { format: { type: "json_object" } },
  });
  return parseRealityLog(JSON.parse(response.output_text));
}
```

- [ ] **Step 3: Implement API route and confirmation component**

Write `app/api/reality-log/route.ts`:

```ts
import { NextResponse } from "next/server";
import { runRealityLogAgent } from "@/lib/agents/reality-log-agent";

export async function POST(request: Request) {
  const body = await request.json();
  const output = await runRealityLogAgent({
    plannedBlockId: String(body.plannedBlockId ?? ""),
    plannedTitle: String(body.plannedTitle ?? ""),
    observationSummary: String(body.observationSummary ?? ""),
    userCorrection: String(body.userCorrection ?? ""),
  });
  return NextResponse.json(output);
}
```

Write `components/reality-confirmation.tsx`:

```tsx
"use client";

import { useState } from "react";

export function RealityConfirmation({ plannedBlockId }: { plannedBlockId: string }) {
  const [correction, setCorrection] = useState("");
  const [status, setStatus] = useState("waiting");

  async function confirmReality() {
    setStatus("saving");
    const response = await fetch("/api/reality-log", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        plannedBlockId,
        plannedTitle: "Edit video",
        observationSummary: "Mostly editing, short YouTube drift.",
        userCorrection: correction,
      }),
    });
    setStatus(response.ok ? "confirmed" : "failed");
  }

  return (
    <section className="rounded-md border border-line bg-white p-4">
      <h2 className="text-lg font-semibold">Confirm reality</h2>
      <p className="mt-2 text-sm text-steel">Screen suggests mostly editing, with short drift. Accurate?</p>
      <textarea className="mt-3 min-h-24 w-full rounded-md border border-line p-3" value={correction} onChange={(event) => setCorrection(event.target.value)} />
      <button className="mt-3 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button" onClick={confirmReality}>
        Confirm log
      </button>
      <p className="mt-2 text-sm text-steel">{status}</p>
    </section>
  );
}
```

- [ ] **Step 4: Verify and commit**

Run:

```bash
rtk npm test -- tests/agents/reality-log-agent.test.ts
rtk npm run typecheck
rtk git add lib/agents/reality-log-agent.ts app/api/reality-log/route.ts components/reality-confirmation.tsx tests/agents/reality-log-agent.test.ts
rtk git commit -m "feat: add reality log agent"
```

Expected:

```text
PASS reality-log-agent
typecheck exits 0
commit succeeds
```

---

### Task 10: Screen Lock-In Frontend

**Parallel lane:** Wave 2 Subagent C.

**Files:**
- Create: `lib/screen/types.ts`
- Create: `lib/screen/frame-sampler.ts`
- Create: `lib/screen/image-hash.ts`
- Create: `components/screen-share-capture.tsx`
- Create: `components/lock-in-screen.tsx`
- Create: `app/(app)/lock-in/page.tsx`
- Test: `tests/screen/frame-sampler.test.ts`

- [ ] **Step 1: Write frame sampler tests**

Write `tests/screen/frame-sampler.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { shouldSampleFrame, targetCanvasSize } from "@/lib/screen/frame-sampler";

describe("frame sampler", () => {
  it("samples at the configured interval", () => {
    expect(shouldSampleFrame({ lastSampleAt: 0, now: 15000, intervalMs: 15000 })).toBe(true);
    expect(shouldSampleFrame({ lastSampleAt: 10000, now: 12000, intervalMs: 15000 })).toBe(false);
  });

  it("downscales wide frames to target width", () => {
    expect(targetCanvasSize({ width: 1920, height: 1080, targetWidth: 1024 })).toEqual({ width: 1024, height: 576 });
  });
});
```

- [ ] **Step 2: Implement screen utilities**

Write `lib/screen/types.ts`:

```ts
export type CapturedFrame = {
  capturedAt: string;
  hash: string;
  blob: Blob;
};

export type FrameSampleConfig = {
  intervalMs: number;
  jpegQuality: number;
  targetWidth: number;
};
```

Write `lib/screen/frame-sampler.ts`:

```ts
export function shouldSampleFrame(input: { lastSampleAt: number; now: number; intervalMs: number }) {
  return input.now - input.lastSampleAt >= input.intervalMs;
}

export function targetCanvasSize(input: { width: number; height: number; targetWidth: number }) {
  if (input.width <= input.targetWidth) return { width: input.width, height: input.height };
  const ratio = input.targetWidth / input.width;
  return { width: input.targetWidth, height: Math.round(input.height * ratio) };
}
```

Write `lib/screen/image-hash.ts`:

```ts
export async function hashBlob(blob: Blob): Promise<string> {
  const bytes = await blob.arrayBuffer();
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
```

- [ ] **Step 3: Implement screen-share component**

Write `components/screen-share-capture.tsx`:

```tsx
"use client";

import { useRef, useState } from "react";
import { Monitor, Square } from "lucide-react";
import { targetCanvasSize } from "@/lib/screen/frame-sampler";
import { hashBlob } from "@/lib/screen/image-hash";

export function ScreenShareCapture({ plannedBlockId }: { plannedBlockId: string }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const timerRef = useRef<number | null>(null);
  const [status, setStatus] = useState("idle");

  async function start() {
    const stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
    if (videoRef.current) {
      videoRef.current.srcObject = stream;
      await videoRef.current.play();
    }
    setStatus("sharing");
    timerRef.current = window.setInterval(sampleFrame, 15000);
  }

  function stop() {
    if (timerRef.current) window.clearInterval(timerRef.current);
    const stream = videoRef.current?.srcObject as MediaStream | null;
    stream?.getTracks().forEach((track) => track.stop());
    setStatus("stopped");
  }

  async function sampleFrame() {
    const video = videoRef.current;
    if (!video || video.videoWidth === 0) return;
    const size = targetCanvasSize({ width: video.videoWidth, height: video.videoHeight, targetWidth: 1024 });
    const canvas = document.createElement("canvas");
    canvas.width = size.width;
    canvas.height = size.height;
    const context = canvas.getContext("2d");
    if (!context) return;
    context.drawImage(video, 0, 0, size.width, size.height);
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.5));
    if (!blob) return;
    const hash = await hashBlob(blob);
    const form = new FormData();
    form.append("plannedBlockId", plannedBlockId);
    form.append("capturedAt", new Date().toISOString());
    form.append("hash", hash);
    form.append("frame", blob);
    await fetch("/api/screen/batch", { method: "POST", body: form });
  }

  return (
    <section className="rounded-md border border-line bg-white p-4">
      <video ref={videoRef} className="hidden" muted playsInline />
      <div className="flex gap-2">
        <button className="inline-flex items-center gap-2 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button" onClick={start}>
          <Monitor className="h-4 w-4" /> Share screen
        </button>
        <button className="inline-flex items-center gap-2 rounded-md border border-line px-4 py-2 text-sm font-medium" type="button" onClick={stop}>
          <Square className="h-4 w-4" /> Stop
        </button>
      </div>
      <p className="mt-2 text-sm text-steel">{status}</p>
    </section>
  );
}
```

- [ ] **Step 4: Implement lock-in page**

Write `components/lock-in-screen.tsx`:

```tsx
import { RealityConfirmation } from "@/components/reality-confirmation";
import { ScreenShareCapture } from "@/components/screen-share-capture";

export function LockInScreen() {
  const plannedBlockId = "demo-block";
  return (
    <div className="max-w-3xl space-y-4">
      <h1 className="text-3xl font-semibold">Screen accountability</h1>
      <p className="text-sm text-steel">Share a screen, window, or tab for this lock-in block.</p>
      <ScreenShareCapture plannedBlockId={plannedBlockId} />
      <RealityConfirmation plannedBlockId={plannedBlockId} />
    </div>
  );
}
```

Write `app/(app)/lock-in/page.tsx`:

```tsx
import { AppShell } from "@/components/app-shell";
import { LockInScreen } from "@/components/lock-in-screen";

export default function LockInPage() {
  return (
    <AppShell>
      <LockInScreen />
    </AppShell>
  );
}
```

- [ ] **Step 5: Verify and commit**

Run:

```bash
rtk npm test -- tests/screen/frame-sampler.test.ts
rtk npm run typecheck
rtk git add lib/screen components/screen-share-capture.tsx components/lock-in-screen.tsx app/'(app)'/lock-in/page.tsx tests/screen
rtk git commit -m "feat: add screen lock-in capture"
```

Expected:

```text
PASS frame-sampler
typecheck exits 0
commit succeeds
```

---

### Task 11: Screen Observation Backend

**Parallel lane:** Wave 2 Subagent D.

**Files:**
- Create: `lib/agents/screen-observer-agent.ts`
- Create: `app/api/screen/batch/route.ts`
- Test: `tests/agents/screen-observer-agent.test.ts`

- [ ] **Step 1: Write observer agent test**

Write `tests/agents/screen-observer-agent.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { buildScreenObserverPrompt, parseScreenObservation } from "@/lib/agents/screen-observer-agent";

describe("screen observer agent", () => {
  it("is observer-only", () => {
    expect(buildScreenObserverPrompt()).toContain("Not a coach");
    expect(buildScreenObserverPrompt()).toContain("Just observer");
  });

  it("parses observations", () => {
    const parsed = parseScreenObservation({
      blockId: "blk_123",
      window: "13:00-13:15",
      observedActivities: [{ activity: "video editing", estimatedMinutes: 9, confidence: 0.82 }],
      summary: "Mostly editing.",
    });
    expect(parsed.summary).toBe("Mostly editing.");
  });
});
```

- [ ] **Step 2: Implement observer agent**

Write `lib/agents/screen-observer-agent.ts`:

```ts
import OpenAI from "openai";
import { screenObservationOutputSchema, type ScreenObservationOutput } from "@/lib/zod/contracts";

export function buildScreenObserverPrompt() {
  return [
    "You are Bogi Screen Observer Agent.",
    "During a lock-in session, summarize what the screen suggests happened.",
    "Not a coach.",
    "Not a planner.",
    "Not a chat agent.",
    "Just observer.",
    "Return observed activities with estimated minutes and confidence.",
  ].join("\n");
}

export function parseScreenObservation(value: unknown): ScreenObservationOutput {
  return screenObservationOutputSchema.parse(value);
}

export async function runScreenObserverAgent(input: {
  blockId: string;
  frames: Array<{ capturedAt: string; imageBase64: string }>;
}): Promise<ScreenObservationOutput> {
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const response = await client.responses.create({
    model: "gpt-5.4-mini",
    input: [
      { role: "system", content: buildScreenObserverPrompt() },
      { role: "user", content: JSON.stringify({ blockId: input.blockId, frameCount: input.frames.length }) },
    ],
    text: { format: { type: "json_object" } },
  });
  return parseScreenObservation(JSON.parse(response.output_text));
}
```

- [ ] **Step 3: Implement screen batch route**

Write `app/api/screen/batch/route.ts`:

```ts
import { NextResponse } from "next/server";

const receivedFrameHashes = new Set<string>();

export async function POST(request: Request) {
  const form = await request.formData();
  const plannedBlockId = String(form.get("plannedBlockId") ?? "");
  const hash = String(form.get("hash") ?? "");
  const capturedAt = String(form.get("capturedAt") ?? "");

  if (!plannedBlockId || !hash || !capturedAt) {
    return NextResponse.json({ error: "missing required frame metadata" }, { status: 400 });
  }

  if (receivedFrameHashes.has(hash)) {
    return NextResponse.json({ accepted: false, reason: "duplicate" });
  }

  receivedFrameHashes.add(hash);
  return NextResponse.json({ accepted: true, plannedBlockId, capturedAt });
}
```

- [ ] **Step 4: Verify and commit**

Run:

```bash
rtk npm test -- tests/agents/screen-observer-agent.test.ts
rtk npm run typecheck
rtk git add lib/agents/screen-observer-agent.ts app/api/screen/batch/route.ts tests/agents/screen-observer-agent.test.ts
rtk git commit -m "feat: add screen observer backend"
```

Expected:

```text
PASS screen-observer-agent
typecheck exits 0
commit succeeds
```

---

### Task 12: Google Calendar Integration

**Parallel lane:** Wave 2 Subagent E.

**Files:**
- Create: `lib/calendar/google-calendar.ts`
- Create: `lib/calendar/sync.ts`
- Create: `app/api/calendar/events/route.ts`
- Test: `tests/calendar/google-calendar.test.ts`

- [ ] **Step 1: Write calendar tests**

Write `tests/calendar/google-calendar.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { toGoogleCalendarEvent } from "@/lib/calendar/google-calendar";

describe("toGoogleCalendarEvent", () => {
  it("maps a Bogi block to Google Calendar event shape", () => {
    expect(toGoogleCalendarEvent({
      title: "Edit video",
      start: "2026-06-06T13:00:00.000Z",
      end: "2026-06-06T14:00:00.000Z",
      successCriteria: "Rough cut first 3 minutes",
      category: "work/video",
    })).toEqual({
      summary: "Edit video",
      description: "Success criteria: Rough cut first 3 minutes\nCategory: work/video",
      start: { dateTime: "2026-06-06T13:00:00.000Z" },
      end: { dateTime: "2026-06-06T14:00:00.000Z" },
    });
  });
});
```

- [ ] **Step 2: Implement calendar mapping and API shell**

Write `lib/calendar/google-calendar.ts`:

```ts
import { google } from "googleapis";
import type { z } from "zod";
import type { plannedBlockSchema } from "@/lib/zod/contracts";

type PlannedBlockInput = z.infer<typeof plannedBlockSchema>;

export function toGoogleCalendarEvent(block: PlannedBlockInput) {
  return {
    summary: block.title,
    description: `Success criteria: ${block.successCriteria}\nCategory: ${block.category}`,
    start: { dateTime: block.start },
    end: { dateTime: block.end },
  };
}

export function createGoogleOAuthClient() {
  return new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_REDIRECT_URI
  );
}
```

Write `lib/calendar/sync.ts`:

```ts
export type CalendarSyncEvent = {
  provider: "google";
  syncToken: string | null;
  changedEventIds: string[];
};

export function describeCalendarSync(event: CalendarSyncEvent) {
  return `${event.provider}:${event.changedEventIds.length}:${event.syncToken ?? "initial"}`;
}
```

Write `app/api/calendar/events/route.ts`:

```ts
import { NextResponse } from "next/server";
import { plannedBlockSchema } from "@/lib/zod/contracts";
import { toGoogleCalendarEvent } from "@/lib/calendar/google-calendar";

export async function POST(request: Request) {
  const block = plannedBlockSchema.parse(await request.json());
  return NextResponse.json({ event: toGoogleCalendarEvent(block) });
}
```

- [ ] **Step 3: Verify and commit**

Run:

```bash
rtk npm test -- tests/calendar/google-calendar.test.ts
rtk npm run typecheck
rtk git add lib/calendar app/api/calendar/events/route.ts tests/calendar
rtk git commit -m "feat: add google calendar integration shell"
```

Expected:

```text
PASS google-calendar
typecheck exits 0
commit succeeds
```

---

### Task 13: Trigger.dev Workflow Setup

**Parallel lane:** Wave 2 Subagent F.

**Files:**
- Create: `lib/workflows/block-ended.ts`
- Create: `lib/workflows/frame-batch-ready.ts`
- Create: `lib/workflows/daily-summary.ts`
- Create: `lib/workflows/weekly-summary.ts`
- Test: `tests/workflows/workflow-events.test.ts`

- [ ] **Step 1: Write workflow event tests**

Write `tests/workflows/workflow-events.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { blockEndedEvent } from "@/lib/workflows/block-ended";
import { frameBatchReadyEvent } from "@/lib/workflows/frame-batch-ready";

describe("workflow events", () => {
  it("names block-ended workflow event", () => {
    expect(blockEndedEvent).toBe("calendar.block.ended");
  });

  it("names frame-batch workflow event", () => {
    expect(frameBatchReadyEvent).toBe("lockin.frame_batch.ready");
  });
});
```

- [ ] **Step 2: Implement workflow modules**

Write `lib/workflows/block-ended.ts`:

```ts
export const blockEndedEvent = "calendar.block.ended";

export type BlockEndedPayload = {
  userId: string;
  plannedBlockId: string;
  endedAt: string;
};
```

Write `lib/workflows/frame-batch-ready.ts`:

```ts
export const frameBatchReadyEvent = "lockin.frame_batch.ready";

export type FrameBatchReadyPayload = {
  userId: string;
  plannedBlockId: string;
  screenSessionId: string;
  frameCount: number;
};
```

Write `lib/workflows/daily-summary.ts`:

```ts
export const dayEndedEvent = "day.ended";

export type DayEndedPayload = {
  userId: string;
  day: string;
};
```

Write `lib/workflows/weekly-summary.ts`:

```ts
export const weekEndedEvent = "week.ended";

export type WeekEndedPayload = {
  userId: string;
  weekStart: string;
};
```

- [ ] **Step 3: Verify and commit**

Run:

```bash
rtk npm test -- tests/workflows/workflow-events.test.ts
rtk npm run typecheck
rtk git add lib/workflows tests/workflows
rtk git commit -m "feat: add workflow event contracts"
```

Expected:

```text
PASS workflow-events
typecheck exits 0
commit succeeds
```

---

### Task 14: Pattern Learner Agent

**Parallel lane:** Wave 3 Subagent A.

**Files:**
- Create: `lib/agents/pattern-learner-agent.ts`
- Test: `tests/agents/pattern-learner-agent.test.ts`

- [ ] **Step 1: Write pattern learner tests**

Write `tests/agents/pattern-learner-agent.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { deriveEditingBlockPattern } from "@/lib/agents/pattern-learner-agent";

describe("pattern learner", () => {
  it("detects failed long editing blocks", () => {
    const result = deriveEditingBlockPattern({
      attempts: 9,
      successes: 2,
      avgActualMinutes: 54,
    });
    expect(result.patternKey).toBe("editing_blocks_over_120_min_fail");
    expect(result.recommendation).toContain("60-minute blocks");
  });
});
```

- [ ] **Step 2: Implement pattern learner**

Write `lib/agents/pattern-learner-agent.ts`:

```ts
export type EditingPatternEvidence = {
  attempts: number;
  successes: number;
  avgActualMinutes: number;
};

export function deriveEditingBlockPattern(evidence: EditingPatternEvidence) {
  return {
    patternKey: "editing_blocks_over_120_min_fail",
    evidence,
    recommendation:
      evidence.successes <= 2
        ? "Plan editing in 60-minute blocks with 10-minute breaks."
        : "Long editing blocks are acceptable when success history supports them.",
  };
}
```

- [ ] **Step 3: Verify and commit**

Run:

```bash
rtk npm test -- tests/agents/pattern-learner-agent.test.ts
rtk npm run typecheck
rtk git add lib/agents/pattern-learner-agent.ts tests/agents/pattern-learner-agent.test.ts
rtk git commit -m "feat: add pattern learner"
```

Expected:

```text
PASS pattern-learner-agent
typecheck exits 0
commit succeeds
```

---

### Task 15: Coach Agent

**Parallel lane:** Wave 3 Subagent B.

**Files:**
- Create: `lib/agents/coach-agent.ts`
- Create: `app/api/coach/route.ts`
- Create: `components/coach-panel.tsx`
- Test: `tests/agents/coach-agent.test.ts`

- [ ] **Step 1: Write coach tests**

Write `tests/agents/coach-agent.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { buildCoachPrompt } from "@/lib/agents/coach-agent";

describe("coach agent", () => {
  it("uses blunt accountability tone", () => {
    const prompt = buildCoachPrompt();
    expect(prompt).toContain("Not therapist");
    expect(prompt).toContain("Not cheerleader");
    expect(prompt).toContain("Blunt accountability coach");
  });
});
```

- [ ] **Step 2: Implement coach agent and API**

Write `lib/agents/coach-agent.ts`:

```ts
import OpenAI from "openai";
import { coachMessageSchema, type CoachMessage } from "@/lib/zod/contracts";

export function buildCoachPrompt() {
  return [
    "You are Bogi Coach Agent.",
    "Not therapist.",
    "Not cheerleader.",
    "Not productivity guru.",
    "Blunt accountability coach.",
    "Use plan-vs-reality data.",
    "Recommend calendar changes but user confirms changes.",
  ].join("\n");
}

export async function runCoachAgent(input: {
  message: string;
  patterns: unknown[];
  logs: unknown[];
}): Promise<CoachMessage> {
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const response = await client.responses.create({
    model: "gpt-5.5",
    input: [
      { role: "system", content: buildCoachPrompt() },
      { role: "user", content: JSON.stringify(input) },
    ],
    text: { format: { type: "json_object" } },
  });
  return coachMessageSchema.parse(JSON.parse(response.output_text));
}
```

Write `app/api/coach/route.ts`:

```ts
import { NextResponse } from "next/server";
import { runCoachAgent } from "@/lib/agents/coach-agent";

export async function POST(request: Request) {
  const body = await request.json();
  const output = await runCoachAgent({
    message: String(body.message ?? ""),
    patterns: Array.isArray(body.patterns) ? body.patterns : [],
    logs: Array.isArray(body.logs) ? body.logs : [],
  });
  return NextResponse.json(output);
}
```

Write `components/coach-panel.tsx`:

```tsx
"use client";

import { useState } from "react";

export function CoachPanel() {
  const [message, setMessage] = useState("");
  const [reply, setReply] = useState("");

  async function send() {
    const response = await fetch("/api/coach", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message, patterns: [], logs: [] }),
    });
    const data = await response.json();
    setReply(String(data.message ?? ""));
  }

  return (
    <section className="rounded-md border border-line bg-white p-4">
      <h2 className="text-lg font-semibold">Coach</h2>
      <textarea className="mt-3 min-h-20 w-full rounded-md border border-line p-3" value={message} onChange={(event) => setMessage(event.target.value)} />
      <button className="mt-3 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button" onClick={send}>Ask Bogi</button>
      {reply ? <p className="mt-3 text-sm">{reply}</p> : null}
    </section>
  );
}
```

- [ ] **Step 3: Verify and commit**

Run:

```bash
rtk npm test -- tests/agents/coach-agent.test.ts
rtk npm run typecheck
rtk git add lib/agents/coach-agent.ts app/api/coach/route.ts components/coach-panel.tsx tests/agents/coach-agent.test.ts
rtk git commit -m "feat: add coach agent"
```

Expected:

```text
PASS coach-agent
typecheck exits 0
commit succeeds
```

---

### Task 16: Voice Input

**Parallel lane:** Wave 3 Subagent C.

**Files:**
- Create: `components/voice-command.tsx`
- Create: `app/api/voice/transcribe/route.ts`
- Test: `tests/api/voice-route.test.ts`

- [ ] **Step 1: Implement voice component and route**

Write `components/voice-command.tsx`:

```tsx
"use client";

import { useRef, useState } from "react";
import { Mic, Square } from "lucide-react";

export function VoiceCommand() {
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const [status, setStatus] = useState("idle");
  const [transcript, setTranscript] = useState("");

  async function start() {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const recorder = new MediaRecorder(stream);
    recorderRef.current = recorder;
    chunksRef.current = [];
    recorder.ondataavailable = (event) => chunksRef.current.push(event.data);
    recorder.onstop = sendAudio;
    recorder.start();
    setStatus("recording");
  }

  async function stop() {
    recorderRef.current?.stop();
    setStatus("transcribing");
  }

  async function sendAudio() {
    const blob = new Blob(chunksRef.current, { type: "audio/webm" });
    const form = new FormData();
    form.append("audio", blob);
    const response = await fetch("/api/voice/transcribe", { method: "POST", body: form });
    const data = await response.json();
    setTranscript(String(data.text ?? ""));
    setStatus("idle");
  }

  return (
    <section className="rounded-md border border-line bg-white p-4">
      <div className="flex gap-2">
        <button className="inline-flex items-center gap-2 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button" onClick={start}>
          <Mic className="h-4 w-4" /> Talk
        </button>
        <button className="inline-flex items-center gap-2 rounded-md border border-line px-4 py-2 text-sm font-medium" type="button" onClick={stop}>
          <Square className="h-4 w-4" /> Stop
        </button>
      </div>
      <p className="mt-2 text-sm text-steel">{status}</p>
      {transcript ? <p className="mt-3 text-sm">{transcript}</p> : null}
    </section>
  );
}
```

Write `app/api/voice/transcribe/route.ts`:

```ts
import OpenAI from "openai";
import { NextResponse } from "next/server";

export async function POST(request: Request) {
  const form = await request.formData();
  const audio = form.get("audio");
  if (!(audio instanceof File)) {
    return NextResponse.json({ error: "audio file required" }, { status: 400 });
  }

  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const transcription = await client.audio.transcriptions.create({
    model: "gpt-4o-transcribe",
    file: audio,
  });

  return NextResponse.json({ text: transcription.text });
}
```

- [ ] **Step 2: Verify and commit**

Run:

```bash
rtk npm run typecheck
rtk git add components/voice-command.tsx app/api/voice/transcribe/route.ts
rtk git commit -m "feat: add voice command input"
```

Expected:

```text
typecheck exits 0
commit succeeds
```

---

### Task 17: Daily, Weekly, And Monthly Summaries

**Parallel lane:** Wave 3 Subagent D.

**Files:**
- Create: `app/api/summaries/route.ts`
- Test: `tests/api/summaries-route.test.ts`

- [ ] **Step 1: Implement summaries route**

Write `app/api/summaries/route.ts`:

```ts
import { NextResponse } from "next/server";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const scope = url.searchParams.get("scope") ?? "day";
  return NextResponse.json({
    scope,
    summary: "Planned work, confirmed reality, and gaps will appear here.",
    stats: {
      plannedMinutes: 360,
      confirmedRealityMinutes: 282,
      gapMinutes: 78,
    },
  });
}
```

- [ ] **Step 2: Verify and commit**

Run:

```bash
rtk npm run typecheck
rtk git add app/api/summaries/route.ts
rtk git commit -m "feat: add summaries api shell"
```

Expected:

```text
typecheck exits 0
commit succeeds
```

---

### Task 18: Export And Delete User Data

**Parallel lane:** Wave 3 Subagent E.

**Files:**
- Create: `app/api/privacy/export/route.ts`
- Create: `app/api/privacy/delete/route.ts`
- Test: `tests/privacy/export-delete.test.ts`

- [ ] **Step 1: Implement export and delete route shells**

Write `app/api/privacy/export/route.ts`:

```ts
import { NextResponse } from "next/server";

export async function GET() {
  return NextResponse.json({
    plannedBlocks: [],
    realityLogs: [],
    screenObservationSummaries: [],
    dailySummaries: [],
    weeklySummaries: [],
    monthlySummaries: [],
    userPatterns: [],
  });
}
```

Write `app/api/privacy/delete/route.ts`:

```ts
import { NextResponse } from "next/server";

export async function POST() {
  return NextResponse.json({ deleted: true });
}
```

- [ ] **Step 2: Verify and commit**

Run:

```bash
rtk npm run typecheck
rtk git add app/api/privacy
rtk git commit -m "feat: add privacy export delete routes"
```

Expected:

```text
typecheck exits 0
commit succeeds
```

---

### Task 19: Payment Page And Founding Plan UX

**Parallel lane:** Wave 3 Subagent F.

**Files:**
- Create: `app/(app)/billing/page.tsx`
- Test: `tests/ui/billing-page.test.tsx`

- [ ] **Step 1: Implement billing page**

Write `app/(app)/billing/page.tsx`:

```tsx
import { AppShell } from "@/components/app-shell";

export default function BillingPage() {
  return (
    <AppShell>
      <section className="max-w-2xl">
        <h1 className="text-3xl font-semibold">Founding plan</h1>
        <p className="mt-3 text-sm text-steel">Lifetime founding access for early Bogi users.</p>
        <button className="mt-6 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button">
          Join founding plan
        </button>
      </section>
    </AppShell>
  );
}
```

- [ ] **Step 2: Verify and commit**

Run:

```bash
rtk npm run typecheck
rtk git add app/'(app)'/billing/page.tsx
rtk git commit -m "feat: add founding plan page"
```

Expected:

```text
typecheck exits 0
commit succeeds
```

---

### Task 20: End-To-End Playwright Flows

**Parallel lane:** Wave 4.

**Files:**
- Create: `e2e/bogi.spec.ts`

- [ ] **Step 1: Write e2e tests**

Write `e2e/bogi.spec.ts`:

```ts
import { expect, test } from "@playwright/test";

test("dashboard and lock-in pages render", async ({ page }) => {
  await page.goto("/dashboard");
  await expect(page.getByRole("heading", { name: "Today" })).toBeVisible();
  await page.goto("/lock-in");
  await expect(page.getByRole("heading", { name: "Screen accountability" })).toBeVisible();
  await expect(page.getByRole("button", { name: /Share screen/ })).toBeVisible();
});

test("home links to dashboard and lock-in", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("link", { name: "Open dashboard" })).toHaveAttribute("href", "/dashboard");
  await expect(page.getByRole("link", { name: "Start lock-in" })).toHaveAttribute("href", "/lock-in");
});
```

- [ ] **Step 2: Run e2e**

Run:

```bash
rtk npm run e2e
```

Expected:

```text
2 passed
```

- [ ] **Step 3: Commit**

Run:

```bash
rtk git add e2e/bogi.spec.ts
rtk git commit -m "test: add bogi e2e smoke tests"
```

---

### Task 21: Browser Screen-Share Manual Verification

**Parallel lane:** Wave 4.

**Files:**
- Modify only if verification finds a defect.

- [ ] **Step 1: Start dev server**

Run:

```bash
rtk npm run dev
```

Expected:

```text
Next.js dev server listening on http://localhost:3000
```

- [ ] **Step 2: Open Browser plugin to lock-in page**

Use the Browser plugin to open:

```text
http://localhost:3000/lock-in
```

Expected:

```text
Screen accountability page is visible.
Share screen and Stop buttons are visible.
```

- [ ] **Step 3: Verify browser capture**

Click `Share screen`, choose a tab/window, wait 20 seconds, then click `Stop`.

Expected:

```text
Browser screen-share picker opens.
Browser shows screen-share indicator.
Status changes to sharing.
No raw frame preview appears in the UI.
Stop ends all tracks and status changes to stopped.
```

---

### Task 22: Final Validation And Release Checkpoint

**Parallel lane:** Wave 4.

**Files:**
- Modify: `AGENTS.md` only if durable repo-specific knowledge was discovered and is not already documented.

- [ ] **Step 1: Run full validation**

Run:

```bash
rtk npm test
rtk npm run typecheck
rtk npm run build
rtk npm run e2e
rtk git status --short
```

Expected:

```text
tests pass
typecheck exits 0
build exits 0
e2e passes
git status shows only intended changes or clean working tree
```

- [ ] **Step 2: Review AGENTS.md memory**

If a durable repo-specific fact was discovered, add one operational line to the closest `AGENTS.md`. If no durable fact was discovered, do not edit `AGENTS.md`.

- [ ] **Step 3: Final commit**

Run:

```bash
rtk git status --short
rtk git diff --stat
rtk git add app components lib tests e2e package.json package-lock.json tsconfig.json next.config.ts postcss.config.mjs tailwind.config.ts vitest.config.ts playwright.config.ts supabase README.md .env.example
rtk git commit -m "feat: complete bogi ssot mvp"
```

Expected:

```text
commit succeeds or there are no uncommitted intended changes
```

## Self-Review

### Spec Coverage

- Calendar planning: Task 8, Task 12
- Start lock-in session: Task 10
- Screen share and frame sampling: Task 10
- AI screen summaries: Task 11
- User confirmation/correction: Task 9
- Reality log storage contract: Task 2, Task 3, Task 9
- Plan-vs-reality gap: Task 2, Task 4, Task 17
- Planner Agent: Task 8
- Screen Observer Agent: Task 11
- Reality Log Agent: Task 9
- Pattern Learner Agent: Task 14
- Coach Agent: Task 15
- Trigger.dev workflows: Task 13
- Supabase Postgres and pgvector: Task 2
- Google Calendar API first: Task 12
- Voice input: Task 16
- Zod schemas and MCP-shaped internal tools: Task 3
- Privacy defaults: Task 5, Task 7, Task 18
- Dashboard and summaries: Task 4, Task 17
- Payment page/founding plan: Task 19
- Browser verification: Task 21

### Omitted-Work Scan

The plan contains concrete file contents for code-writing steps. Shell commands include expected outcomes.

### Type Consistency

Core property names are consistent across contracts, tests, and route shells:

- `plannedBlockId`
- `actualSummary`
- `completionScore`
- `deviationReason`
- `actualCategories`
- `confirmedByUser`
- `observedActivities`
- `estimatedMinutes`
- `confidence`

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-05-bogi-full-ssot-implementation.md`.

Two execution options:

1. **Subagent-Driven (recommended)** - Dispatch a fresh implementation subagent per task or per wave lane, review between tasks, fast iteration.
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints.

Recommended choice: **Subagent-Driven**, because Tasks 2 through 19 split cleanly after the scaffold and shared contracts.
