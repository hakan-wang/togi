# User Chat Mockup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the first-run experience with a user-facing Togi chat mockup backed by the existing planner, reality-log, and coach services.

**Architecture:** Add `/api/chat` as a lightweight orchestrator over existing services. Add `/` as a client chat UI with a conversation pane and state sidebars. Leave `/test-console` available as an internal debug page.

**Tech Stack:** Next.js 15 App Router, React 19, TypeScript, Zod, Vitest.

---

## Files

- Create: `src/app/api/chat/route.ts` - one-shot chat orchestrator.
- Create: `src/app/api/chat/route.test.ts` - route behavior tests.
- Create: `src/app/page.tsx` - user-facing chat mockup.
- Create: `src/app/page.test.ts` - static page coverage test.

## Tasks

- [ ] Write route tests first:
  - planning messages return persisted planned block artifacts.
  - ordinary coach messages return a coach response and current state.
- [ ] Verify route tests fail because `/api/chat` is missing.
- [ ] Write page static test first:
  - root page contains user-facing chat copy and no testing-suite framing.
- [ ] Verify page test fails because `/` page is missing.
- [ ] Implement `/api/chat`.
- [ ] Implement `/`.
- [ ] Run targeted tests.
- [ ] Run `npm run typecheck`, `npm run lint`, `npm test`, `npm run build`.
- [ ] Commit focused changes.
- [ ] Relaunch `npm run dev` normally so `.env.local` provides the API key.
