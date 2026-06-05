# User Chat Mockup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:using-git-worktrees first, then use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Togi user chat experience from scratch as a real LangChain tool-calling agent, not a one-shot OpenAI wrapper.

**Architecture:** The previous plan was wrong: it treated chat as a thin `/api/chat` orchestrator that guessed planner/reality/coach modes and then patched over live inference failures with raw OpenAI HTTPS. That is not the product direction. The rebuild must use LangChain `createAgent()` with real tools for reading and writing Togi state, and the UI should call this single agent route.

**Tech Stack:** Next.js 15 App Router, React 19, TypeScript, Zod, Vitest, LangChain `createAgent()`, `@langchain/core` tools, `@langchain/openai` model integration, optional `@langchain/langgraph` memory/checkpointing.

---

## Critical Correction

Do not continue from the current implementation.

The current branch contains intentionally superseded work:

- `/api/chat` is a one-shot router, not an agent loop.
- `agent-runtime.ts` bypasses SDKs with raw HTTPS, which fixed live inference but removed agent/tool semantics.
- The UI can display plans, but the model does not decide tool calls.
- Fallback text hid the real failure instead of building the correct architecture.

The next implementation must happen in a fresh worktree and should replace these choices rather than extend them.

## Required New Worktree

- [ ] Create a new isolated worktree before coding.
- [ ] Start from a branch state before the raw-HTTPS/runtime workaround if possible.
- [ ] If starting from this branch, first remove the raw runtime direction and replace `/api/chat` with LangChain agent code.
- [ ] Keep all server launches on ports `3000`, `3001`, `3002`, `3003`, or `3004`; never use ports above `3004`.

## Files To Create Or Replace

- Replace: `src/app/api/chat/route.ts` - LangChain agent endpoint.
- Create: `src/server/services/chat/langchain-agent.ts` - `createAgent()` setup and invocation.
- Create: `src/server/services/chat/tools.ts` - LangChain tools over existing Togi services.
- Create: `src/server/services/chat/schemas.ts` - shared Zod schemas for agent request/response artifacts.
- Create: `src/server/services/chat/langchain-agent.test.ts` - tool-call behavior tests.
- Replace or create: `src/app/page.tsx` - user-facing chat UI.
- Replace or create: `src/app/page.test.ts` - static/product framing tests.
- Modify: `package.json` and `package-lock.json` - add LangChain dependencies only after confirming versions.

## Agent Tools

Define tools with `tool()` from `@langchain/core/tools`.

Required tools:

- `list_goals`
  - Input: none.
  - Output: active and recent goals for the authenticated user.
- `list_planned_blocks`
  - Input: optional status filter.
  - Output: planned blocks for the authenticated user.
- `create_planned_block`
  - Input: title, start time, end time, intention text, success criteria, category.
  - Output: persisted planned block.
- `draft_reality_log`
  - Input: planned block id and user answer.
  - Output: draft reality log, not persisted truth.
- `list_reality_logs`
  - Input: none.
  - Output: recent confirmed reality logs.
- `coach_from_history`
  - Input: user question.
  - Output: coaching answer grounded in goals, plans, and logs.

Rules:

- The model must be able to call tools.
- Persistence happens only through tools.
- Reality logs are not persisted unless the user explicitly confirms.
- The response to the UI must include both assistant text and any tool artifacts.

## Task 1: Dependency And Transport Verification

- [ ] Add LangChain dependencies:

```bash
npm install langchain @langchain/core @langchain/openai @langchain/langgraph
```

- [ ] Write a small verification script or test that invokes a LangChain OpenAI model with the current `.env.local`.
- [ ] Verify it reaches live OpenAI without `codex-lb`.
- [ ] If LangChain's OpenAI integration routes through `codex-lb`, stop and document the blocker before coding the app.

## Task 2: Tool Tests First

- [ ] Write tests for each tool in `src/server/services/chat/tools.test.ts`.
- [ ] Verify tests fail before tools exist.
- [ ] Implement tools by calling existing services from `src/server/services/container.ts`.
- [ ] Verify tests pass.

Expected assertions:

- `create_planned_block` persists a checkable block.
- `list_planned_blocks` returns the created block.
- `draft_reality_log` returns a draft and does not persist it.
- `coach_from_history` returns grounded text.

## Task 3: Agent Loop Tests First

- [ ] Write `src/server/services/chat/langchain-agent.test.ts`.
- [ ] Test that a planning request causes the agent to call `create_planned_block`.
- [ ] Test that a check-in request calls `draft_reality_log` and not persistence.
- [ ] Test that a general coaching request can call read tools.
- [ ] Verify tests fail before the agent exists.
- [ ] Implement `createAgent()` with the tools.
- [ ] Verify tests pass.

The agent must use `createAgent()`. Do not use ad hoc router heuristics as the primary behavior.

## Task 4: API Route

- [ ] Write failing tests for `src/app/api/chat/route.ts`.
- [ ] Implement the route as a thin wrapper around the LangChain agent service.
- [ ] Route input:

```ts
{
  message: string;
  threadId?: string;
}
```

- [ ] Route output:

```ts
{
  assistantMessage: string;
  toolCalls: Array<{ name: string; status: "completed" | "failed" }>;
  artifacts: {
    plannedBlocks: PlannedBlock[];
    realityDraft: RealityLogAgentOutput | null;
  };
  state: {
    goals: Goal[];
    plannedBlocks: PlannedBlock[];
    realityLogs: RealityLog[];
  };
}
```

## Task 5: User UI

- [ ] Build `/` as a real user mockup:
  - chat thread
  - composer
  - suggested prompts
  - plan cards
  - reality draft cards
  - today/sidebar state
- [ ] Do not show JSON, bearer tokens, endpoint names, smoke-test controls, or testing-suite framing.
- [ ] Show tool activity in user-facing language, e.g. "Created a plan block" instead of raw tool traces.

## Task 6: Verification

- [ ] Run:

```bash
npm run typecheck
npm run lint
npm test
npm run build
```

- [ ] Launch only on an allowed port:

```bash
npm run dev -- -p 3000
```

- [ ] Manually verify:
  - planning prompt creates a planned block through a tool call;
  - check-in prompt drafts a reality log through a tool call;
  - coach prompt reads state through tools;
  - no `codex-lb` error appears;
  - no server uses ports above `3004`.

## Definition Of Done

- LangChain is installed and used.
- `createAgent()` owns the chat loop.
- At least one live inference request calls a tool.
- The UI is user-facing, not a testing suite.
- Tests prove tool behavior.
- The old one-shot/raw-runtime mistake is not repeated.
