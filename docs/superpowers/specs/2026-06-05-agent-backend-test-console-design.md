# Agent Backend Test Console Design

## Context

Togi currently has backend-only Next.js API routes under `src/app/api/**`.
The test console adds a temporary developer UI for exercising every implemented backend feature without pretending to be the real product frontend.

## Goal

Create a Next.js page at `/test-console` that can call all implemented backend routes with editable inputs, a shared bearer token, visible status codes, and formatted JSON responses.

## Covered Features

- `GET /api/health`
- `GET /api/goals`, `POST /api/goals`, `PATCH /api/goals/:id`
- `GET /api/planned-blocks`, `POST /api/planned-blocks`, `GET /api/planned-blocks/:id`, `PATCH /api/planned-blocks/:id`, `DELETE /api/planned-blocks/:id`
- `GET /api/reality-logs`, `POST /api/reality-logs`, `GET /api/reality-logs/:id`, `PATCH /api/reality-logs/:id`
- `POST /api/agents/planner`
- `POST /api/agents/reality-log`
- `POST /api/agents/coach`
- `GET /api/patterns`
- `GET /api/calendar/google/connect`
- `GET /api/calendar/google/callback?code=...`
- `POST /api/calendar/google/sync`

## UX

The page is a dense internal console, not a polished customer UI.

- Shared bearer token input defaults to `api-user`.
- Each feature group has prefilled JSON/text inputs and explicit run buttons.
- Results show method, path, HTTP status, elapsed time, and formatted response body.
- Created goal, planned block, and reality-log IDs are stored in local page state so follow-up get/patch/delete actions can use them.
- A "Run all smoke tests" action exercises representative calls across the full API surface.

## Implementation

- Add a client component page under `src/app/test-console/page.tsx`.
- Use browser `fetch` against same-origin `/api/**` routes.
- Keep state local to the page.
- Use inline CSS or a local CSS module only if needed; avoid new dependencies.
- Do not change backend route behavior.

## Verification

- `npm run typecheck`
- `npm run lint`
- `npm test`
- `npm run build`
- Start `npm run dev` and verify `/test-console` loads.
