# Agent Backend Test Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `/test-console` Next.js page that exercises every implemented Togi backend route from the browser.

**Architecture:** Add one client-rendered App Router page that uses same-origin `fetch` and local React state. The backend API routes stay unchanged. A smoke test verifies the route file exists and contains the expected feature sections.

**Tech Stack:** Next.js 15 App Router, React 19, TypeScript, Vitest.

---

## Files

- Create: `src/app/test-console/page.tsx` - client test console UI and fetch helpers.
- Create: `src/app/test-console/page.test.ts` - static route coverage test.

## Task 1: Route Coverage Test

- [ ] **Step 1: Write the failing test**

Create `src/app/test-console/page.test.ts`:

```ts
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const source = () => readFileSync("src/app/test-console/page.tsx", "utf8");

describe("test console page", () => {
  it("covers every implemented backend feature group", () => {
    const page = source();

    for (const label of [
      "Health",
      "Goals",
      "Planned Blocks",
      "Reality Logs",
      "Agents",
      "Patterns",
      "Google Calendar"
    ]) {
      expect(page).toContain(label);
    }

    for (const route of [
      "/api/health",
      "/api/goals",
      "/api/planned-blocks",
      "/api/reality-logs",
      "/api/agents/planner",
      "/api/agents/reality-log",
      "/api/agents/coach",
      "/api/patterns",
      "/api/calendar/google/connect",
      "/api/calendar/google/callback?code=test-code",
      "/api/calendar/google/sync"
    ]) {
      expect(page).toContain(route);
    }
  });
});
```

- [ ] **Step 2: Verify the test fails**

Run: `npm test -- src/app/test-console/page.test.ts`
Expected: FAIL because `src/app/test-console/page.tsx` does not exist.

## Task 2: Test Console Page

- [ ] **Step 1: Implement the page**

Create `src/app/test-console/page.tsx` as a client component with:

- `token` state defaulting to `api-user`.
- `latestGoalId`, `latestBlockId`, and `latestRealityLogId` state.
- `callApi(method, path, body?)` helper that sends bearer auth, JSON bodies, times requests, and stores formatted results.
- Sections and buttons for each route listed in Task 1.
- Prefilled JSON textarea state for create/patch/agent request bodies.
- `Run all smoke tests` button that calls representative endpoints across the full API surface.

- [ ] **Step 2: Verify targeted test passes**

Run: `npm test -- src/app/test-console/page.test.ts`
Expected: PASS.

## Task 3: Validation

- [ ] **Step 1: Run full checks**

Run:

```bash
npm run typecheck
npm run lint
npm test
npm run build
```

Expected: all pass.

- [ ] **Step 2: Commit implementation**

Run:

```bash
git add src/app/test-console/page.tsx src/app/test-console/page.test.ts
git commit -m "Add agent backend test console"
```

- [ ] **Step 3: Start and verify**

Run: `npm run dev`
Expected: `/test-console` loads and can call at least `/api/health`.
