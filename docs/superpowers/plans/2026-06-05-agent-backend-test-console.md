# Agent Backend Test Console Implementation Plan

> **For agentic workers:** This plan is intentionally downgraded. Do not implement this before the real LangChain chat agent plan. Use this only as optional internal debug tooling after the user-facing agent loop exists.

**Goal:** Preserve the idea of a backend debug console as optional tooling, while preventing it from being mistaken for the product UI.

**Architecture:** The previous plan over-prioritized a comprehensive endpoint test console. That was useful for backend smoke testing, but it was the wrong first UI for this product. The primary plan must be the LangChain tool-calling chat agent; this console is secondary and should not drive product architecture.

**Tech Stack:** Next.js 15 App Router, React 19, TypeScript, Vitest.

---

## Correction

The old implementation path was wrong because it made the first visible UI a test harness:

- raw endpoint controls;
- bearer-token input;
- smoke-test buttons;
- JSON request bodies;
- no real user conversation loop.

For the rebuild, do not start here.

## When This Plan Is Allowed

Only implement this after:

- LangChain dependencies are installed;
- `/api/chat` uses `createAgent()`;
- tools can read and write Togi state;
- the user-facing `/` chat mockup works;
- live inference can call at least one tool.

## Optional Files

- `src/app/test-console/page.tsx` - internal debug UI.
- `src/app/test-console/page.test.ts` - static route coverage test.

## Optional Scope

If implemented, the console may include:

- health check;
- goals routes;
- planned block routes;
- reality log routes;
- calendar boundary routes;
- read-only view of recent agent/tool runs.

It must not be presented as the product UI.

## Constraints

- Do not add or change agent architecture from this plan.
- Do not use this plan to justify one-shot chat routing.
- Do not add fallback text that hides live agent failures.
- Keep server ports at `3000`, `3001`, `3002`, `3003`, or `3004`.

## Verification

If implemented later, run:

```bash
npm run typecheck
npm run lint
npm test
npm run build
```

Then launch on an allowed port only:

```bash
npm run dev -- -p 3000
```
