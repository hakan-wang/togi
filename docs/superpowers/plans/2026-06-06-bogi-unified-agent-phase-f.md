# Bogi Unified Agent — Phase F: Full Unification + WebSocket Streaming + Review Fixes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** (1) Fix the 5 must-fix bugs the final review found; (2) collapse the last separate path — activity segmentation — into the single agent loop (the agent segments via a `record_segments` tool, queries history via read tools, and nudges, all on the user's machine); (3) move the agent↔backend hop to a WebSocket so model turns stream token-by-token to the UI.

**Architecture:** The 5-minute tick now invokes the one LangChain agent with the recent observations + active plan. The agent calls tools: `record_segments` (write labeled blocks to local SQLite via Swift), read tools (`search_activity`/`summarize_range`/`list_days`/`list_goals`), and `post_nudge`. The structured `JudgeService` inference call is retired. The sidecar talks to a new API Gateway **WebSocket** endpoint that runs Bedrock `ConverseStream`; text deltas stream sidecar→app as `token` RPC frames and render incrementally in the Coach UI. HTTP `/v1/infer` remains as a non-streaming fallback.

**Tech Stack:** unchanged + `ws` (sidecar WebSocket client), API Gateway WebSocket API + `@aws-sdk/client-apigatewaymanagementapi` (backend), `ConverseStreamCommand`.

**Builds on:** `docs/superpowers/specs/2026-06-06-bogi-unified-agent-design.md` (this phase supersedes the "segmentation stays structured" decision: segmentation is now part of the agent loop).

---

## File Structure

**F1 — Review bug fixes**
- Modify `apps/macos/Bogi/sidecar/src/proxyChatModel.ts` — drop system messages from `toInferMessages`; check HTTP status.
- Modify `apps/macos/Bogi/sidecar/src/main.ts` — `post` checks `r.ok`.
- Modify `apps/macos/Bogi/Packaging/build-app.sh` — ship full node_modules closure; sign all `.node`.
- Modify `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarTransport.swift` — recreate `Process`/pipes per `start()`.
- Modify `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarClient.swift` — real exponential backoff.

**F2 — Full unification (segmentation → agent)**
- Create `apps/macos/Bogi/sidecar/src/tools/recordTools.ts` — `record_segments` action tool.
- Modify `apps/macos/Bogi/sidecar/src/main.ts` — register record tool; add a `judge` message kind.
- Modify `apps/macos/Bogi/sidecar/src/persona.ts` — describe the segmentation duty.
- Modify `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarActionHandlers.swift` — `record_segments` handler → `SegmentStore`.
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeCoordinator.swift` — tick forwards observations to the agent; remove `JudgeService` inference.
- Delete `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeService.swift` and its tests; keep `JudgeResult.swift` types (used by the record tool payload + tests).
- Modify `apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift` — drop `JudgeService` construction; pass `SegmentStore` to action handlers.

**F3 — WebSocket streaming**
- Create `backend/src/wsHandler.mjs` — `$connect`/`$disconnect`/`infer` routes; Bedrock `ConverseStream`; push frames via management API.
- Create `backend/test/wsHandler.test.mjs` — pure stream-event → frame mapping tests.
- Create `backend/ws-apigw.sh` — create/deploy the WebSocket API + routes + integration.
- Modify `apps/macos/Bogi/sidecar/src/proxyChatModel.ts` — stream over WebSocket; `onToken` callback.
- Modify `apps/macos/Bogi/sidecar/src/main.ts` — emit `token` frames during chat; pass WS URL from env.
- Modify `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarClient.swift` — surface `token` frames via an `onToken` per-request callback.
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Coach/CoachService.swift` — streaming `ask` (AsyncStream).
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Coach/CoachView.swift` + `AppDelegate.swift` — render incremental tokens.

---

# F1 — Review bug fixes

## Task F1.1: proxyChatModel drops system messages + checks status

**Files:** Modify `apps/macos/Bogi/sidecar/src/proxyChatModel.ts`; Test `apps/macos/Bogi/sidecar/test/proxyChatModel.test.ts`

- [ ] **Step 1: Failing test** — append:

```typescript
import { SystemMessage, HumanMessage } from "@langchain/core/messages";

test("system messages are not sent as user turns (Converse needs alternating roles)", async () => {
  let captured: any;
  const model = new BogiProxyChatModel({
    post: async (body) => { captured = body; return { text: "ok", stopReason: "end_turn", content: [{ type: "text", text: "ok" }] }; },
    system: "PERSONA",
  });
  await model.invoke([new SystemMessage("PERSONA"), new HumanMessage("hi")]);
  const roles = captured.messages.map((m: any) => m.role);
  expect(roles).toEqual(["user"]); // the system message must be filtered out, not mapped to user
});
```

- [ ] **Step 2: Run → fail.** `cd apps/macos/Bogi/sidecar && npm test` — expect roles `["user","user"]`.

- [ ] **Step 3: Fix `toInferMessages`** — filter system messages at the top:

```typescript
function toInferMessages(messages: BaseMessage[]): InferRequest["messages"] {
  return messages
    .filter((m) => m.getType() !== "system")
    .map((m) => {
      // ...existing mapping unchanged...
    });
}
```

(PERSONA still reaches the model via the `system` field set in `createBogiAgent`.)

- [ ] **Step 4: Run → pass.** `npm test`.

- [ ] **Step 5: Commit** — `fix(sidecar): never send system messages as user turns (Converse alternation)` + Co-Authored-By trailer.

## Task F1.2: sidecar `post` checks HTTP status

**Files:** Modify `apps/macos/Bogi/sidecar/src/main.ts`

- [ ] **Step 1:** In `runStdio`'s `post`, replace the body with a status check:

```typescript
  const post = async (body: unknown) => {
    const r = await fetch(`${baseURL}/v1/infer`, {
      method: "POST",
      headers: { "content-type": "application/json", "X-Bogi-Authorization": `Bearer ${token}` },
      body: JSON.stringify(body),
    });
    const raw = await r.text();
    if (!r.ok) throw new Error(`backend ${r.status}: ${raw.slice(0, 300)}`);
    return JSON.parse(raw) as any;
  };
```

- [ ] **Step 2:** Build to verify: `npm run build` produces `dist/main.cjs`.

- [ ] **Step 3: Commit** — `fix(sidecar): surface backend HTTP errors instead of crashing on non-200`.

## Task F1.3: ProcessSidecarTransport recreatable + real backoff

**Files:** Modify `SidecarTransport.swift`, `SidecarClient.swift`; Test `SidecarClientTests.swift`

- [ ] **Step 1: Failing test** — extend `FakeTransport` so `start()` throws if started twice unless reset (to model the real `Process` constraint), then assert restart still works. Simpler and sufficient: assert that after a crash, `start()` is invoked on a transport that reports `startCount == 2` AND that a second crash schedules a longer delay. Add:

```swift
func testBackoffGrowsBetweenCrashes() async throws {
    let transport = FakeTransport()
    let client = SidecarClient(transport: transport, restartDelay: 0.01)
    try client.start()
    transport.simulateCrash()
    try await Task.sleep(nanoseconds: 60_000_000)
    let afterFirst = transport.startCount
    transport.simulateCrash()
    try await Task.sleep(nanoseconds: 60_000_000)
    XCTAssertGreaterThan(transport.startCount, afterFirst)
}
```

- [ ] **Step 2: Run → fail/observe.** `cd apps/macos/Bogi && swift test --filter SidecarClientTests`.

- [ ] **Step 3: Fix the transport** — in `ProcessSidecarTransport`, change `process`/`stdinPipe`/`stdoutPipe` from stored `let` to `var` created fresh in `start()`:

```swift
    private var process = Process()
    private var stdinPipe = Pipe()
    private var stdoutPipe = Pipe()

    func start() throws {
        process = Process()
        stdinPipe = Pipe()
        stdoutPipe = Pipe()
        buffer = Data()
        // ...existing setup (executableURL, arguments, environment, pipes, readabilityHandler, terminationHandler)...
        try process.run()
    }
```

- [ ] **Step 4: Real backoff in `SidecarClient`** — track attempts and grow the delay:

```swift
    private var restartAttempts = 0

    private func handleTermination() {
        lock.lock()
        let waiting = pending; pending.removeAll()
        restartAttempts += 1
        let attempt = restartAttempts
        lock.unlock()
        for (_, cont) in waiting { cont.resume(throwing: SidecarError.terminated) }
        let delay = min(restartDelay * pow(2, Double(attempt - 1)), 30)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            try? self?.transport.start()
        }
    }
```

Reset `restartAttempts = 0` whenever a line is successfully received (in `handle(_:)` after a valid decode), so a healthy sidecar clears the backoff.

- [ ] **Step 5: Run → pass.** `swift test --filter SidecarClientTests`.

- [ ] **Step 6: Commit** — `fix(app): recreate Process on restart + exponential backoff`.

## Task F1.4: build-app.sh ships full native dep closure

**Files:** Modify `apps/macos/Bogi/Packaging/build-app.sh`

- [ ] **Step 1:** Replace the "copy only better-sqlite3" line with copying the whole production `node_modules` (the bundle's `external: ["better-sqlite3"]` means only native deps need shipping; copying all of `node_modules` is the simplest correct closure):

```bash
# Ship the sidecar's node_modules so native deps (better-sqlite3 -> bindings -> file-uri-to-path) resolve.
cp -R "$SIDECAR_SRC/node_modules" "$SIDECAR_DST/node_modules"
```

Update the `NODE_PATH` used at launch (AppDelegate) to point at `Resources/sidecar/node_modules` (see Task note) — but since `main.cjs` lives in `Resources/sidecar/`, Node resolves `Resources/sidecar/node_modules` automatically; the explicit `NODE_PATH` can be dropped or set to `Resources/sidecar/node_modules`.

- [ ] **Step 2:** Generalize the codesign-of-native-modules step to the whole copied tree:

```bash
find "$RESOURCES/sidecar/node_modules" -name "*.node" -print0 | \
  while IFS= read -r -d '' f; do
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$f"
  done
```

- [ ] **Step 3:** Verify packaged layout resolves (no signing identity needed for this check):

```bash
cd apps/macos/Bogi/sidecar && npm run build && \
mkdir -p /tmp/bogi-pkg-test && cp dist/main.cjs /tmp/bogi-pkg-test/ && cp -R node_modules /tmp/bogi-pkg-test/ && \
node -e "const D=require('/tmp/bogi-pkg-test/node_modules/better-sqlite3'); const db=new D(':memory:'); db.exec('create table t(x)'); console.log('db-ok');"
```
Expected: prints `db-ok`.

- [ ] **Step 4: Commit** — `fix(build): ship full sidecar node_modules so better-sqlite3 resolves natively`.

---

# F2 — Full unification: segmentation becomes the agent loop

## Task F2.1: `record_segments` tool (sidecar)

**Files:** Create `apps/macos/Bogi/sidecar/src/tools/recordTools.ts`; Test `apps/macos/Bogi/sidecar/test/recordTools.test.ts`

The agent calls this to persist the time blocks it segmented. It is an action tool (round-trips to Swift, which writes SQLite). Payload mirrors `JudgeSegment`.

- [ ] **Step 1: Failing test** — `test/recordTools.test.ts`:

```typescript
import { test, expect } from "vitest";
import { makeRecordTools } from "../src/tools/recordTools.js";

test("record_segments forwards the segments to the host", async () => {
  const seen: any[] = [];
  const tools = makeRecordTools(async (name, input) => { seen.push({ name, input }); return { ok: true, count: (input as any).segments.length }; });
  const rec = tools.find((t) => t.name === "record_segments")!;
  const out = JSON.parse(await rec.invoke({ segments: [
    { start_at: "2026-06-06T10:00:00Z", end_at: "2026-06-06T10:05:00Z", minutes: 5, category: "Work", sub_category: "Coding", sub_sub: "Editing", on_task: true, confidence: 0.9 },
  ] }));
  expect(out).toEqual({ ok: true, count: 1 });
  expect(seen[0].name).toBe("record_segments");
});
```

- [ ] **Step 2: Run → fail.** `npm test`.

- [ ] **Step 3: Implement `src/tools/recordTools.ts`**

```typescript
import { tool } from "@langchain/core/tools";
import { z } from "zod";
import { type StructuredToolInterface } from "@langchain/core/tools";
import { type CallAction } from "./actionTools.js";

const segment = z.object({
  start_at: z.string(), end_at: z.string(), minutes: z.number(),
  category: z.string().nullish(), sub_category: z.string().nullish(), sub_sub: z.string().nullish(),
  on_task: z.boolean().nullish(), confidence: z.number().nullish(),
});

export function makeRecordTools(callAction: CallAction): StructuredToolInterface[] {
  const record_segments = tool(
    async (input) => JSON.stringify(await callAction("record_segments", input)),
    {
      name: "record_segments",
      description: "Persist the labeled time segments you produced from the last few minutes of activity. Call this exactly once per activity review, after segmenting the observations into category / sub_category / sub_sub blocks with minutes and on_task.",
      schema: z.object({ segments: z.array(segment) }),
    }
  );
  return [record_segments];
}
```

- [ ] **Step 4: Run → pass.** `npm test`.

- [ ] **Step 5: Commit** — `feat(sidecar): record_segments tool for agent-driven segmentation`.

## Task F2.2: register record tool + `judge` message kind (sidecar)

**Files:** Modify `apps/macos/Bogi/sidecar/src/main.ts`, `src/rpc.ts`, `src/persona.ts`

- [ ] **Step 1:** In `rpc.ts`, the `judge` inbound kind already maps to the same handling as `chat`/`plan` (it carries `text`). Add it to the `Inbound` union: `{ kind: "judge"; id: string; threadId: string; text: string }`. In `main.ts` `makeDispatcher`, accept `kind === "judge"` alongside `chat`/`plan`.

- [ ] **Step 2:** In `runStdio`, include the record tools:

```typescript
  const { makeRecordTools } = await import("./tools/recordTools.js");
  const tools = [
    ...makeReadTools(() => openReadOnly(dbPath)),
    ...makeActionTools(callAction),
    ...makeRecordTools(callAction),
  ];
```

- [ ] **Step 3:** Extend `persona.ts` with the segmentation duty:

```typescript
// append to PERSONA:
`

When given a batch of recent on-screen observations and the planned block, your job is to:
1) Segment the activity into time blocks (category, sub_category, sub_sub, minutes, on_task) and call record_segments once with them.
2) Decide whether the user has drifted off their plan. If they have sustainedly drifted, call post_nudge with a kind, supportive message. If they are on task or there is no plan, do not nudge.
You may call the data tools to compare against history before deciding.`
```

- [ ] **Step 4:** Build + existing tests green: `npm test && npm run build`.

- [ ] **Step 5: Commit** — `feat(sidecar): register record tool, add judge tick path, segmentation persona`.

## Task F2.3: Swift `record_segments` handler → SegmentStore

**Files:** Modify `SidecarActionHandlers.swift`; Test `SidecarActionHandlerTests.swift`

- [ ] **Step 1: Failing test** — add:

```swift
func testRecordSegmentsPersists() async throws {
    var inserted: [ActivitySegment] = []
    let handlers = SidecarActionHandlers(
        createBlock: { _,_,_ in nil }, moveBlock: { _,_,_ in nil },
        postNudge: { _,_ in },
        recordSegments: { segs in inserted = segs; return segs.count })
    let input: [String: Any] = ["segments": [[
        "start_at": "2026-06-06T10:00:00Z", "end_at": "2026-06-06T10:05:00Z",
        "minutes": 5, "category": "Work", "sub_category": "Coding", "sub_sub": "Editing",
        "on_task": true, "confidence": 0.9,
    ]]]
    let result = await handlers.handle("record_segments", input)
    XCTAssertEqual(result["ok"] as? Bool, true)
    XCTAssertEqual(result["count"] as? Int, 1)
    XCTAssertEqual(inserted.first?.category, "Work")
    XCTAssertEqual(inserted.first?.onTask, true)
}
```

- [ ] **Step 2: Run → fail.** `swift test --filter SidecarActionHandlerTests`.

- [ ] **Step 3: Implement** — add a `RecordSegments` closure type and case to `SidecarActionHandlers`:

```swift
    typealias RecordSegments = (_ segments: [ActivitySegment]) async -> Int
    // store it; add to init.

        case "record_segments":
            guard let rows = input["segments"] as? [[String: Any]] else { return ["ok": false, "error": "bad_input"] }
            let now = Date()
            let segs: [ActivitySegment] = rows.compactMap { r in
                guard let start = date(r["start_at"]), let end = date(r["end_at"]),
                      let minutes = r["minutes"] as? Double ?? (r["minutes"] as? Int).map(Double.init) else { return nil }
                return ActivitySegment(
                    id: UUID().uuidString, startAt: start, endAt: end, minutes: minutes,
                    plannedBlockId: nil, category: r["category"] as? String,
                    subCategory: r["sub_category"] as? String, subSub: r["sub_sub"] as? String,
                    onTask: r["on_task"] as? Bool, confidence: r["confidence"] as? Double, judgedAt: now)
            }
            let count = await recordSegments(segs)
            return ["ok": true, "count": count]
```

- [ ] **Step 4: Run → pass.** `swift test --filter SidecarActionHandlerTests`.

- [ ] **Step 5: Commit** — `feat(app): record_segments handler persists agent-segmented blocks`.

## Task F2.4: Coordinator forwards ticks to the agent; retire JudgeService

**Files:** Modify `JudgeCoordinator.swift`, `AppDelegate.swift`; Delete `JudgeService.swift`; update/delete `JudgeTests.swift` segmentation tests; Test as noted.

- [ ] **Step 1:** Rewrite `JudgeCoordinator.tick()` to forward to the agent instead of calling `JudgeService`. It builds the same `JudgeInput` JSON (reuse `JudgePrompt.userJSON`) and sends it as a `judge` message:

```swift
    func tick() async {
        let now = Date()
        let recent = observations.recent(within: interval, now: now)
        guard !recent.isEmpty else { return }
        let obs = recent.map {
            (t: $0.capturedAt, app: $0.activeApp, window: $0.activeWindowTitle, text: $0.text, focused: $0.focused)
        }
        let active = blocks.activeBlock(at: now)
        let input = JudgeInput(
            activeBlock: active.map { (title: $0.title, category: $0.category, startAt: $0.startAt, endAt: $0.endAt) },
            observations: obs, recentOffTaskMinutes: 0)
        let payload = JudgePrompt.userJSON(input)
        _ = try? await sidecar.judge(payload, threadId: "judge")
    }
```

Remove the `judge: JudgeService`, `nudgeGate`, `presenter`-based result routing from the coordinator's responsibilities that are now the agent's (the agent calls `record_segments` + `post_nudge`; `post_nudge` already routes to the presenter via the action handler). Keep `SidecarClient` injected; drop `JudgeService`/`NudgeGate` params (or keep `NudgeGate` unused-removed). Update `AppDelegate` construction accordingly.

- [ ] **Step 2:** Add `SidecarClient.judge(_:threadId:)` mirroring `plan` (sends `kind: "judge"`).

- [ ] **Step 3:** Delete `JudgeService.swift` and the `JudgeTests` cases that exercised `runOnce`/structured nudging (`testSegmentationPromptIsSegmentationOnly` and any `runOnce` tests). Keep `JudgeOutput`/`JudgeSegment` parsing tests only if still used; `JudgeResult.swift` (`JudgeSegment`) stays (referenced by the record handler test). `JudgePrompt.userJSON` stays (used to build the tick payload); its `system` constant is now unused and can be removed.

- [ ] **Step 4:** In `AppDelegate`, remove `JudgeService` construction and pass the `SegmentStore` into `SidecarActionHandlers` (the `recordSegments` closure: `{ segs in await MainActor.run { segs.forEach { segmentStore.insert($0) }; return segs.count } }`).

- [ ] **Step 5:** Build + test: `swift build && swift test`. Fix any references to removed symbols. Full suite green.

- [ ] **Step 6: Commit** — `feat(judge): route the 5-min tick through the unified agent (retire JudgeService)`.

---

# F3 — WebSocket streaming

## Task F3.1: Backend WebSocket handler (pure mapping + handler)

**Files:** Create `backend/src/wsHandler.mjs`, `backend/test/wsHandler.test.mjs`

The handler serves three routes on an API Gateway WebSocket API: `$connect` (authorize via `?token=`), `$disconnect` (noop), and `infer` (run `ConverseStream`, push frames back via the management API). Factor the Bedrock-stream-event → client-frame mapping into a pure function for testing.

- [ ] **Step 1: Failing test** — `backend/test/wsHandler.test.mjs`:

```javascript
import test from "node:test";
import assert from "node:assert/strict";
import { streamEventToFrame } from "../src/wsHandler.mjs";

test("contentBlockDelta text -> delta frame", () => {
  assert.deepEqual(
    streamEventToFrame({ contentBlockDelta: { delta: { text: "hel" } } }),
    { type: "delta", text: "hel" }
  );
});
test("toolUse start -> tool_use frame", () => {
  assert.deepEqual(
    streamEventToFrame({ contentBlockStart: { start: { toolUse: { toolUseId: "t1", name: "search_activity" } } } }),
    { type: "tool_use_start", id: "t1", name: "search_activity" }
  );
});
test("messageStop -> stop frame", () => {
  assert.deepEqual(
    streamEventToFrame({ messageStop: { stopReason: "tool_use" } }),
    { type: "stop", stopReason: "tool_use" }
  );
});
test("unknown event -> null", () => {
  assert.equal(streamEventToFrame({ metadata: {} }), null);
});
```

- [ ] **Step 2: Run → fail.** `cd backend && node --test`.

- [ ] **Step 3: Implement `backend/src/wsHandler.mjs`**

```javascript
import { BedrockRuntimeClient, ConverseStreamCommand } from "@aws-sdk/client-bedrock-runtime";
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from "@aws-sdk/client-apigatewaymanagementapi";
import { buildConverseInput } from "./converse.mjs";

const REGION = process.env.BEDROCK_REGION || "eu-west-1";
const MODEL_ID = process.env.BEDROCK_MODEL_ID || "eu.anthropic.claude-sonnet-4-6";
const bedrock = new BedrockRuntimeClient({ region: REGION });

// Pure: map one Bedrock ConverseStream event to a client frame (or null to skip).
export function streamEventToFrame(ev) {
  if (ev.contentBlockDelta?.delta?.text != null) return { type: "delta", text: ev.contentBlockDelta.delta.text };
  if (ev.contentBlockDelta?.delta?.toolUse?.input != null) return { type: "tool_use_delta", input: ev.contentBlockDelta.delta.toolUse.input };
  const tu = ev.contentBlockStart?.start?.toolUse;
  if (tu) return { type: "tool_use_start", id: tu.toolUseId, name: tu.name };
  if (ev.messageStop) return { type: "stop", stopReason: ev.messageStop.stopReason };
  return null;
}

export const handler = async (event) => {
  const route = event?.requestContext?.routeKey;
  if (route === "$connect") return await onConnect(event);
  if (route === "$disconnect") return { statusCode: 200 };
  if (route === "infer") return await onInfer(event);
  return { statusCode: 404 };
};

async function onConnect(event) {
  // Authorize at connect time; token in query string (set by the sidecar).
  const token = event?.queryStringParameters?.token;
  const ok = await authorize(token);
  return { statusCode: ok ? 200 : 401 };
}

async function onInfer(event) {
  const { domainName, stage, connectionId } = event.requestContext;
  const mgmt = new ApiGatewayManagementApiClient({ region: REGION, endpoint: `https://${domainName}/${stage}` });
  const send = (obj) => mgmt.send(new PostToConnectionCommand({ ConnectionId: connectionId, Data: Buffer.from(JSON.stringify(obj)) }));
  let body;
  try { body = JSON.parse(event.body || "{}"); } catch { await send({ type: "error", message: "bad_json" }); return { statusCode: 400 }; }
  try {
    const input = buildConverseInput({ modelId: MODEL_ID, system: body.system, messages: body.messages, tools: body.tools, maxTokens: Math.min(body.maxTokens || 1024, 8192) });
    const res = await bedrock.send(new ConverseStreamCommand(input));
    for await (const ev of res.stream || []) {
      const frame = streamEventToFrame(ev);
      if (frame) await send(frame);
    }
    await send({ type: "done" });
  } catch (err) {
    await send({ type: "error", message: String(err?.message || err) });
  }
  return { statusCode: 200 };
}

async function authorize(token) {
  if (process.env.AUTH_DISABLED === "1") return true;
  if (!token || !process.env.SUPABASE_URL) return false;
  const r = await fetch(`${process.env.SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: process.env.SUPABASE_ANON_KEY || "" },
  });
  return r.ok;
}
```

- [ ] **Step 4: Run → pass.** `node --test`.

- [ ] **Step 5: Commit** — `feat(backend): WebSocket ConverseStream handler + event mapping`.

## Task F3.2: Deploy script for the WebSocket API

**Files:** Create `backend/ws-apigw.sh`

- [ ] **Step 1:** Write `backend/ws-apigw.sh` mirroring the style of `backend/apigw.sh`: create a WebSocket API (`--protocol-type WEBSOCKET --route-selection-expression '$request.body.action'`), a Lambda (or reuse one with `wsHandler.handler`), AWS_PROXY integrations for `$connect`/`$disconnect`/`infer`, deploy a stage, and `lambda add-permission` for `apigateway.amazonaws.com`. Echo the resulting `wss://` URL. Reference `apigw.sh` for account id, region, and role wiring. Include a comment that the Lambda needs `execute-api:ManageConnections` on the API plus the existing Bedrock permissions.

- [ ] **Step 2:** Lint the script: `bash -n backend/ws-apigw.sh`. (Do not run a real deploy unless AWS creds + permissions are present.)

- [ ] **Step 3: Commit** — `feat(backend): WebSocket API deploy script`.

## Task F3.3: Sidecar streams over WebSocket

**Files:** Modify `apps/macos/Bogi/sidecar/src/proxyChatModel.ts`, `src/main.ts`, `package.json`; Test `test/proxyChatModel.test.ts`

The chat model gets a streaming `post` that uses a WebSocket and an `onToken(delta)` callback for text deltas. Inject a `connect` function (returns an object with `send` + async iterator of frames) so tests use a fake, real code uses `ws`.

- [ ] **Step 1: Failing test** — add a streaming test:

```typescript
test("streams text deltas via onToken and returns accumulated content", async () => {
  const deltas: string[] = [];
  const model = new BogiProxyChatModel({
    // fake streaming transport: yields two text deltas then stop
    stream: async function* () {
      yield { type: "delta", text: "Hello " };
      yield { type: "delta", text: "there" };
      yield { type: "stop", stopReason: "end_turn" };
    },
    onToken: (t) => deltas.push(t),
  });
  const res = await model.invoke([new HumanMessage("hi")]);
  expect(deltas).toEqual(["Hello ", "there"]);
  expect(res.content).toBe("Hello there");
});
```

- [ ] **Step 2: Run → fail.** `npm test`.

- [ ] **Step 3: Implement streaming in `proxyChatModel.ts`** — add `stream?` and `onToken?` to the fields; in `_generate`, if `stream` is provided, consume it: accumulate `delta.text` (calling `onToken`), collect `tool_use_start` + `tool_use_delta` into tool_calls, finish on `stop`/`done`, and build the same `AIMessage`. Keep the non-streaming `post` path as fallback. Add `ws` to dependencies for the real connector (used only in `main.ts`).

- [ ] **Step 4:** In `main.ts` `runStdio`, build the real `stream` from a `ws` WebSocket to `process.env.BOGI_WS_URL` with `?token=...`, sending `{ action: "infer", ... }` and yielding parsed frames; wire `onToken: (t) => process.stdout.write(encodeMessage({ kind: "token", id: currentRequestId, text: t }))`. Thread the active request id into the model per dispatch (e.g. set it on the model before `agent.invoke`). If `BOGI_WS_URL` is unset, fall back to the HTTP `post`.

- [ ] **Step 5: Run → pass + build.** `npm test && npm run build`.

- [ ] **Step 6: Commit** — `feat(sidecar): stream model output over WebSocket with onToken`.

## Task F3.4: App renders streamed tokens

**Files:** Modify `SidecarClient.swift`, `CoachService.swift`, `CoachView.swift`, `AppDelegate.swift`; Test `SidecarClientTests.swift`

- [ ] **Step 1: Failing test** — assert `token` frames invoke a per-request token handler:

```swift
func testTokenFramesStreamToHandler() async throws {
    let transport = FakeTransport()
    var streamed = ""
    transport.autoReply = { line in
        guard let id = Self.idFrom(line) else { return nil }
        // emit two tokens then the final result, all for this id
        return #"{"kind":"token","id":"\#(id)","text":"Hel"}"#
    }
    let client = SidecarClient(transport: transport)
    try client.start()
    // Use the streaming API
    let result = try await client.chat("hi", threadId: "t", onToken: { streamed += $0 })
    // (FakeTransport can be extended to also emit a result line; assert streamed contains "Hel")
    XCTAssertTrue(streamed.contains("Hel"))
    _ = result
}
```

(Adapt `FakeTransport` to emit one or more `token` frames followed by a `result` frame for the same id; add an `idFrom` helper. Keep the existing non-streaming `chat` working by making `onToken` optional.)

- [ ] **Step 2: Run → fail.** `swift test --filter SidecarClientTests`.

- [ ] **Step 3:** In `SidecarClient`, add an `onToken` registry keyed by request id; in `handle(_:)` route `kind == "token"` to `tokenHandlers[id]?(text)`. Add `func chat(_:threadId:onToken:)` (and keep the old `chat` delegating with `onToken: nil`). Clear the token handler when the `result`/`error` resolves.

- [ ] **Step 4:** In `CoachService`, add a streaming `ask(_:onToken:)`. In `CoachView`/`AppDelegate` companion wiring, append tokens to the visible reply as they arrive (the closure updates the message text on the main actor), then finalize on completion.

- [ ] **Step 5: Run → pass + build.** `swift test && swift build`.

- [ ] **Step 6: Commit** — `feat(app): render streamed agent tokens in the Coach UI`.

---

# Final verification (Phase F)

- [ ] Backend: `cd backend && node --test` green (converse + infer + wsHandler).
- [ ] Sidecar: `cd apps/macos/Bogi/sidecar && npm test && npm run typecheck && npm run build` green.
- [ ] App: `cd apps/macos/Bogi && swift test` green.
- [ ] Packaged-DB check (F1.4 Step 3) prints `db-ok`.
- [ ] Manual (needs signed build + AWS WS deploy): ask the Coach a question and watch tokens stream in; let a 5-min tick run and confirm the agent both records segments and (when off-task) nudges, all via one agent.
