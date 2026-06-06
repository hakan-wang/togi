# Bogi Unified Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile Bogi's three LLM call sites (Coach, Planner, Judge-nudge) into one LangChain.js agent running in an on-device Node sidecar, with tools that query the local SQLite data bank by keyword + time range, plus an explicit focused-window marker on observations.

**Architecture:** The macOS app keeps capturing locally and segmenting activity with a cheap structured call. A bundled Node sidecar runs `create_agent` (LangChain.js) and talks to Swift over stdio JSON-RPC. Read tools open the local SQLite file read-only (FTS5 + time ranges); action tools (nudge, calendar) round-trip to Swift. Model turns go through the existing backend proxy, which is extended to carry Bedrock Converse tool definitions. Raw data never leaves the device.

**Tech Stack:** Swift/SwiftUI + GRDB (app), Node 22 + TypeScript + LangChain.js + better-sqlite3 (sidecar), Node esbuild + AWS Bedrock Converse (backend Lambda), Vitest (sidecar tests), XCTest (app), `node --test` (backend).

**Spec:** `docs/superpowers/specs/2026-06-06-bogi-unified-agent-design.md`

---

## File Structure

**Phase A — Foundations (app + backend, no sidecar)**
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Capture/CaptureSnapshot.swift` — add `focused`.
- Modify `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/Records.swift` — add `focused`.
- Modify `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/SchemaMigrator.swift` — migration `v3`.
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Capture/AccessibilityCaptureService.swift` — set `focused`.
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Capture/CaptureController.swift` — persist `focused`.
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgePrompt.swift` — carry/emit `focused`.
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeCoordinator.swift` — map `focused`.
- Modify `backend/src/handler.mjs` — tool-capable Converse; extract pure helpers.
- Create `backend/src/converse.mjs` — pure `buildConverseInput` / `parseConverseOutput`.
- Create `backend/test/converse.test.mjs` — backend tests.
- Modify `backend/package.json` — `test` script.

**Phase B — Sidecar skeleton + packaging spike**
- Create `apps/macos/Bogi/sidecar/` — Node/TS project (`package.json`, `tsconfig.json`, `esbuild.mjs`, `vitest.config.ts`).
- Create `apps/macos/Bogi/sidecar/src/rpc.ts` — line-delimited JSON-RPC framing.
- Create `apps/macos/Bogi/sidecar/src/proxyChatModel.ts` — `BogiProxyChatModel`.
- Create `apps/macos/Bogi/sidecar/src/agent.ts` — `createBogiAgent`.
- Create `apps/macos/Bogi/sidecar/src/persona.ts` — single system prompt.
- Create `apps/macos/Bogi/sidecar/src/main.ts` — stdio entrypoint.
- Create `apps/macos/Bogi/sidecar/test/*.test.ts` — sidecar tests.
- Create `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarTransport.swift` — transport protocol + Process impl.
- Create `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarClient.swift` — RPC client.
- Create `apps/macos/Bogi/Tests/BogiAppTests/SidecarClientTests.swift`.
- Modify `apps/macos/Bogi/Packaging/build-app.sh` — embed node + sidecar bundle, codesign.

**Phase C — Read tools + Coach migration**
- Create `apps/macos/Bogi/sidecar/src/db.ts` — read-only SQLite open.
- Create `apps/macos/Bogi/sidecar/src/tools/readTools.ts` — `search_activity`, `summarize_range`, `list_days`, `list_goals`.
- Create `apps/macos/Bogi/sidecar/test/readTools.test.ts`.
- Modify `apps/macos/Bogi/sidecar/src/agent.ts` — register read tools.
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Coach/CoachService.swift` — route through sidecar.
- Modify `apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift` — wire SidecarClient.

**Phase D — Planner via action tools**
- Create `apps/macos/Bogi/sidecar/src/tools/actionTools.ts` — `create_block`, `move_block`.
- Modify `apps/macos/Bogi/sidecar/src/main.ts` — action-call round trip.
- Create `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarActionHandlers.swift`.
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Planner/PlannerService.swift` — route through sidecar.

**Phase E — Nudge gate + agent-owned nudging**
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgePrompt.swift` — drop nudge instruction.
- Create `apps/macos/Bogi/Sources/BogiApp/Features/Judge/NudgeGate.swift` — heuristic.
- Create `apps/macos/Bogi/Tests/BogiAppTests/NudgeGateTests.swift`.
- Modify `apps/macos/Bogi/sidecar/src/tools/actionTools.ts` — `post_nudge`.
- Modify `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeCoordinator.swift` — gate → sidecar nudge_tick.

---

# PHASE A — Foundations

## Task A1: Add `focused` to CaptureSnapshot

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Capture/CaptureSnapshot.swift:5-22`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/CaptureTests.swift`

- [ ] **Step 1: Write the failing test** — append to `CaptureTests.swift`:

```swift
func testSnapshotCarriesFocusedFlag() {
    let snap = CaptureSnapshot(
        activeApp: "Xcode", bundleId: "com.apple.dt.Xcode",
        windowTitle: "Bogi", text: "hello", hasSecureField: false
    )
    XCTAssertTrue(snap.focused, "captured snapshot is the focused window by default")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi && swift test --filter CaptureTests/testSnapshotCarriesFocusedFlag`
Expected: FAIL — `value of type 'CaptureSnapshot' has no member 'focused'`.

- [ ] **Step 3: Add the field** — edit `CaptureSnapshot.swift`:

```swift
struct CaptureSnapshot {
    let activeApp: String?
    let bundleId: String?
    let windowTitle: String?
    let text: String?
    let hasSecureField: Bool
    let focused: Bool
    let contentHash: String

    init(activeApp: String?, bundleId: String?, windowTitle: String?, text: String?,
         hasSecureField: Bool, focused: Bool = true) {
        self.activeApp = activeApp
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.text = text
        self.hasSecureField = hasSecureField
        self.focused = focused
        let basis = "\(bundleId ?? "")|\(windowTitle ?? "")|\(text ?? "")"
        let digest = SHA256.hash(data: Data(basis.utf8))
        self.contentHash = digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

The default `= true` keeps existing call sites compiling (we only capture the focused window today). `focused` is intentionally excluded from `contentHash` (it does not change dedup identity).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos/Bogi && swift test --filter CaptureTests/testSnapshotCarriesFocusedFlag`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Capture/CaptureSnapshot.swift apps/macos/Bogi/Tests/BogiAppTests/CaptureTests.swift
git commit -m "feat(capture): add focused flag to CaptureSnapshot"
```

## Task A2: Add `focused` column + record field

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/Records.swift:5-28`
- Modify: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/SchemaMigrator.swift:126`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/SchemaMigrationTests.swift`

- [ ] **Step 1: Write the failing test** — append to `SchemaMigrationTests.swift`:

```swift
func testObservationsHaveFocusedColumn() throws {
    let db = try DatabaseService(inMemory: true)
    try db.dbQueue.read { conn in
        let cols = try conn.columns(in: "activity_observations").map { $0.name }
        XCTAssertTrue(cols.contains("focused"), "activity_observations needs a focused column")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi && swift test --filter SchemaMigrationTests/testObservationsHaveFocusedColumn`
Expected: FAIL — column not present.

- [ ] **Step 3: Add the migration** — in `SchemaMigrator.swift`, immediately before `try migrator.migrate(dbQueue)` (after the `v2_search` block):

```swift
        // Phase A — explicit focus marker on raw observations (default true: we only
        // capture the focused window today; this is forward-compatible with background capture).
        migrator.registerMigration("v3_observation_focused") { db in
            try db.alter(table: "activity_observations") { t in
                t.add(column: "focused", .boolean).notNull().defaults(to: true)
            }
        }
```

- [ ] **Step 4: Add the record field** — in `Records.swift`, add the property and coding key:

```swift
    var captureMethod: String
    var excluded: Bool
    var focused: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case capturedAt = "captured_at"
        case activeApp = "active_app"
        case activeAppBundleId = "active_app_bundle_id"
        case activeWindowTitle = "active_window_title"
        case text
        case contentHash = "content_hash"
        case captureMethod = "capture_method"
        case excluded
        case focused
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/macos/Bogi && swift test --filter SchemaMigrationTests`
Expected: PASS (both old and new tests).

- [ ] **Step 6: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/SchemaMigrator.swift apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/Records.swift apps/macos/Bogi/Tests/BogiAppTests/SchemaMigrationTests.swift
git commit -m "feat(db): add focused column to activity_observations (migration v3)"
```

## Task A3: Persist `focused` from CaptureController

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Capture/CaptureController.swift:64-74`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/CaptureTests.swift`

- [ ] **Step 1: Write the failing test** — append to `CaptureTests.swift`. (`CaptureTests` already builds a controller with a fake provider + real in-memory store; mirror that setup. If the existing fake provider type differs, reuse it.)

```swift
func testStoredObservationIsMarkedFocused() throws {
    let db = try DatabaseService(inMemory: true)
    let store = ObservationStore(database: db)
    let provider = FakeSnapshotProvider(snapshot: CaptureSnapshot(
        activeApp: "Xcode", bundleId: "com.apple.dt.Xcode",
        windowTitle: "Bogi", text: "writing tests", hasSecureField: false))
    let controller = CaptureController(
        provider: provider, store: store,
        excludes: CaptureExcludes(settings: SettingsStore(database: db)),
        pruner: RetentionPruner(database: db),
        settings: SettingsStore(database: db))
    XCTAssertTrue(controller.performTick())
    let stored = store.recent(within: 3600)
    XCTAssertEqual(stored.first?.focused, true)
}
```

If `CaptureTests.swift` already defines a fake provider with a different name/initializer, use that one instead of `FakeSnapshotProvider`, and reuse its construction helpers for `CaptureExcludes`/`RetentionPruner`/`SettingsStore`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi && swift test --filter CaptureTests/testStoredObservationIsMarkedFocused`
Expected: FAIL — `ActivityObservation` initializer is missing `focused:` (compile error).

- [ ] **Step 3: Pass focused through** — in `CaptureController.performTick()`, update the insert:

```swift
        store.insert(ActivityObservation(
            id: UUID().uuidString,
            capturedAt: clock(),
            activeApp: snap.activeApp,
            activeAppBundleId: snap.bundleId,
            activeWindowTitle: snap.windowTitle,
            text: snap.text,
            contentHash: snap.contentHash,
            captureMethod: "ax",
            excluded: false,
            focused: snap.focused
        ))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos/Bogi && swift test --filter CaptureTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Capture/CaptureController.swift apps/macos/Bogi/Tests/BogiAppTests/CaptureTests.swift
git commit -m "feat(capture): persist focused flag on stored observations"
```

## Task A4: Thread `focused` into the segmentation prompt

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgePrompt.swift:5-9,58-64`
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeCoordinator.swift:49-51`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/JudgeTests.swift`

- [ ] **Step 1: Write the failing test** — append to `JudgeTests.swift`:

```swift
func testUserJSONIncludesFocusedFlag() {
    let input = JudgeInput(
        activeBlock: nil,
        observations: [(t: Date(timeIntervalSince1970: 0), app: "Xcode",
                        window: "Bogi", text: "code", focused: true)],
        recentOffTaskMinutes: 0)
    let json = JudgePrompt.userJSON(input)
    XCTAssertTrue(json.contains("\"focused\""), "observation JSON should carry focused")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi && swift test --filter JudgeTests/testUserJSONIncludesFocusedFlag`
Expected: FAIL — the `observations` tuple has no `focused` label (compile error).

- [ ] **Step 3: Extend `JudgeInput` and `userJSON`** — in `JudgePrompt.swift`:

```swift
struct JudgeInput {
    var activeBlock: (title: String, category: String?, startAt: Date, endAt: Date)?
    var observations: [(t: Date, app: String?, window: String?, text: String?, focused: Bool)]
    var recentOffTaskMinutes: Int
}
```

In `userJSON`, inside the observations map:

```swift
        root["observations"] = input.observations.map { obs -> [String: Any] in
            var o: [String: Any] = ["t": iso.string(from: obs.t), "focused": obs.focused]
            if let app = obs.app { o["app"] = app }
            if let window = obs.window { o["window"] = window }
            if let text = obs.text { o["text"] = text }
            return o
        }
```

- [ ] **Step 4: Update the coordinator mapping** — in `JudgeCoordinator.tick()`:

```swift
        let obs = recent.map {
            (t: $0.capturedAt, app: $0.activeApp, window: $0.activeWindowTitle,
             text: $0.text, focused: $0.focused)
        }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd apps/macos/Bogi && swift test --filter JudgeTests`
Expected: PASS (existing judge tests still green; the `lastSystem == JudgePrompt.system` assertion is unaffected).

- [ ] **Step 6: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgePrompt.swift apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeCoordinator.swift apps/macos/Bogi/Tests/BogiAppTests/JudgeTests.swift
git commit -m "feat(judge): include focused flag per observation in segmentation prompt"
```

## Task A5: Extract pure Converse helpers with tool support

**Files:**
- Create: `backend/src/converse.mjs`
- Test: `backend/test/converse.test.mjs`
- Modify: `backend/package.json`

- [ ] **Step 1: Add the test script** — in `backend/package.json` `"scripts"`:

```json
  "scripts": {
    "build": "esbuild src/handler.mjs --bundle --platform=node --target=node22 --format=esm --outfile=dist/handler.mjs --banner:js=\"import{createRequire}from'module';const require=createRequire(import.meta.url);\"",
    "test": "node --test"
  },
```

- [ ] **Step 2: Write the failing test** — create `backend/test/converse.test.mjs`:

```javascript
import test from "node:test";
import assert from "node:assert/strict";
import { buildConverseInput, parseConverseOutput } from "../src/converse.mjs";

test("text-only request is backward compatible", () => {
  const input = buildConverseInput({
    modelId: "m", system: "be kind",
    messages: [{ role: "user", content: "hi" }],
    maxTokens: 100, temperature: 0,
  });
  assert.equal(input.modelId, "m");
  assert.deepEqual(input.system, [{ text: "be kind" }]);
  assert.deepEqual(input.messages, [{ role: "user", content: [{ text: "hi" }] }]);
  assert.equal(input.toolConfig, undefined);
});

test("tools become a Converse toolConfig", () => {
  const tools = [{
    name: "search_activity",
    description: "search",
    input_schema: { type: "object", properties: { q: { type: "string" } }, required: ["q"] },
  }];
  const input = buildConverseInput({
    modelId: "m", messages: [{ role: "user", content: "find" }], tools, maxTokens: 100,
  });
  assert.equal(input.toolConfig.tools[0].toolSpec.name, "search_activity");
  assert.deepEqual(
    input.toolConfig.tools[0].toolSpec.inputSchema.json,
    tools[0].input_schema
  );
});

test("structured content blocks (tool_result) pass through", () => {
  const input = buildConverseInput({
    modelId: "m",
    messages: [
      { role: "user", content: "find" },
      { role: "assistant", content: [{ type: "tool_use", id: "t1", name: "search_activity", input: { q: "x" } }] },
      { role: "user", content: [{ type: "tool_result", tool_use_id: "t1", content: "3 results" }] },
    ],
    maxTokens: 100,
  });
  assert.deepEqual(input.messages[1].content, [
    { toolUse: { toolUseId: "t1", name: "search_activity", input: { q: "x" } } },
  ]);
  assert.deepEqual(input.messages[2].content, [
    { toolResult: { toolUseId: "t1", content: [{ text: "3 results" }] } },
  ]);
});

test("parseConverseOutput surfaces text, tool_use, stopReason, usage", () => {
  const res = {
    stopReason: "tool_use",
    usage: { inputTokens: 5, outputTokens: 7 },
    output: { message: { role: "assistant", content: [
      { text: "let me look" },
      { toolUse: { toolUseId: "t1", name: "search_activity", input: { q: "x" } } },
    ] } },
  };
  const out = parseConverseOutput(res);
  assert.equal(out.stopReason, "tool_use");
  assert.equal(out.text, "let me look");
  assert.deepEqual(out.content, [
    { type: "text", text: "let me look" },
    { type: "tool_use", id: "t1", name: "search_activity", input: { q: "x" } },
  ]);
  assert.deepEqual(out.usage, { inputTokens: 5, outputTokens: 7 });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd backend && node --test`
Expected: FAIL — cannot find `../src/converse.mjs`.

- [ ] **Step 4: Implement the helpers** — create `backend/src/converse.mjs`:

```javascript
// Pure translation between Bogi's request/response shape and Bedrock Converse.
// No network here so it is unit-testable. Supports text-only (backward compatible)
// and tool use (toolConfig + tool_use / tool_result content blocks).

function toContentBlocks(content) {
  // String content -> a single text block (legacy path).
  if (typeof content === "string") return [{ text: content }];
  // Array of typed blocks -> Converse content blocks.
  return (content || []).map((b) => {
    if (b.type === "text") return { text: b.text };
    if (b.type === "tool_use") {
      return { toolUse: { toolUseId: b.id, name: b.name, input: b.input } };
    }
    if (b.type === "tool_result") {
      const inner = typeof b.content === "string" ? [{ text: b.content }] : b.content;
      return { toolResult: { toolUseId: b.tool_use_id, content: inner } };
    }
    return { text: String(b.text ?? "") };
  });
}

export function buildConverseInput({ modelId, system, messages, tools, maxTokens = 1024, temperature = 0 }) {
  const input = {
    modelId,
    system: system ? [{ text: system }] : undefined,
    messages: (messages || []).map((m) => ({ role: m.role, content: toContentBlocks(m.content) })),
    inferenceConfig: { maxTokens, temperature },
  };
  if (tools && tools.length) {
    input.toolConfig = {
      tools: tools.map((t) => ({
        toolSpec: {
          name: t.name,
          description: t.description,
          inputSchema: { json: t.input_schema },
        },
      })),
    };
  }
  return input;
}

export function parseConverseOutput(res) {
  const blocks = res.output?.message?.content || [];
  const content = blocks.map((b) => {
    if (b.text != null) return { type: "text", text: b.text };
    if (b.toolUse) {
      return { type: "tool_use", id: b.toolUse.toolUseId, name: b.toolUse.name, input: b.toolUse.input };
    }
    return { type: "text", text: "" };
  });
  const text = content.filter((c) => c.type === "text").map((c) => c.text).join("");
  return { text, content, stopReason: res.stopReason, usage: res.usage };
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && node --test`
Expected: PASS — 4 tests.

- [ ] **Step 6: Commit**

```bash
git add backend/src/converse.mjs backend/test/converse.test.mjs backend/package.json
git commit -m "feat(backend): pure Converse helpers with tool-use support"
```

## Task A6: Wire tool passthrough into `/v1/infer`

**Files:**
- Modify: `backend/src/handler.mjs:1,33-43,55-68`

- [ ] **Step 1: Write the failing test** — create `backend/test/infer.test.mjs`:

```javascript
import test from "node:test";
import assert from "node:assert/strict";
import { buildInferResponse } from "../src/handler.mjs";

test("buildInferResponse returns text, content, stopReason for tool calls", () => {
  const parsed = {
    text: "looking",
    content: [{ type: "tool_use", id: "t1", name: "search_activity", input: { q: "x" } }],
    stopReason: "tool_use",
    usage: { outputTokens: 3 },
  };
  const body = buildInferResponse(parsed);
  assert.equal(body.text, "looking");
  assert.equal(body.stopReason, "tool_use");
  assert.equal(body.content[0].type, "tool_use");
  assert.deepEqual(body.usage, { outputTokens: 3 });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test`
Expected: FAIL — `buildInferResponse` is not exported.

- [ ] **Step 3: Refactor the handler to use the pure helpers** — in `backend/src/handler.mjs`:

Replace the import line at the top:

```javascript
import { BedrockRuntimeClient, ConverseCommand } from "@aws-sdk/client-bedrock-runtime";
import crypto from "node:crypto";
import { buildConverseInput, parseConverseOutput } from "./converse.mjs";
```

Replace `callBedrock` with:

```javascript
async function callBedrock({ system, messages, tools, maxTokens = 1024, temperature = 0 }) {
  const cmd = new ConverseCommand(
    buildConverseInput({ modelId: MODEL_ID, system, messages, tools, maxTokens, temperature })
  );
  const res = await bedrock.send(cmd);
  return parseConverseOutput(res);
}

// Shape the /v1/infer JSON body. Exported for tests.
export function buildInferResponse(parsed) {
  return { text: parsed.text, content: parsed.content, stopReason: parsed.stopReason, usage: parsed.usage };
}
```

Replace `infer` with:

```javascript
async function infer(event) {
  const gate = await requirePaidUser(event);
  if (gate.error) return gate.error;

  const body = parseBody(event);
  if (!body?.messages?.length) return json(400, { error: "messages_required" });
  const parsed = await callBedrock({
    system: body.system,
    messages: body.messages,
    tools: body.tools,
    maxTokens: Math.min(body.maxTokens || 1024, 8192),
    temperature: body.temperature ?? 0,
  });
  return json(200, buildInferResponse(parsed));
}
```

`healthz` calls `callBedrock(...)` then reads `.text`; that still works because `parseConverseOutput` returns `{ text, ... }`. Update the `healthz` line `const { text } = await callBedrock(...)` — it already destructures `text`, so no change needed.

- [ ] **Step 4: Run tests + build to verify**

Run: `cd backend && node --test && npm run build`
Expected: tests PASS; esbuild produces `dist/handler.mjs` with no errors.

- [ ] **Step 5: Commit**

```bash
git add backend/src/handler.mjs backend/test/infer.test.mjs
git commit -m "feat(backend): /v1/infer passes tools through and returns content+stopReason"
```

---

# PHASE B — Sidecar skeleton + packaging spike

## Task B0: Spike — embeddable Node runtime under hardened runtime

**Goal:** Confirm we can ship a Node binary inside the `.app`, sign it for hardened runtime + notarization, and launch it from Swift. This de-risks the rest of Phase B before code depends on it.

**Files:** none committed except a short findings note.

- [ ] **Step 1: Download a pinned Node runtime**

Run:
```bash
mkdir -p /tmp/bogi-node && cd /tmp/bogi-node
curl -fsSLO https://nodejs.org/dist/v22.11.0/node-v22.11.0-darwin-arm64.tar.gz
tar xzf node-v22.11.0-darwin-arm64.tar.gz
./node-v22.11.0-darwin-arm64/bin/node -e "console.log('node-ok', process.version)"
```
Expected: prints `node-ok v22.11.0`.

- [ ] **Step 2: Codesign the binary with hardened runtime**

Run (use the same Developer ID identity as `build-app.sh`):
```bash
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <YOUR TEAM>" \
  /tmp/bogi-node/node-v22.11.0-darwin-arm64/bin/node
codesign --verify --verbose /tmp/bogi-node/node-v22.11.0-darwin-arm64/bin/node
```
Expected: `valid on disk` / `satisfies its Designated Requirement`.

- [ ] **Step 3: Confirm the entitlement needs**

Read `apps/macos/Bogi/Packaging/Bogi.entitlements`. Node's JIT needs `com.apple.security.cs.allow-jit` (and, if any native addon is unsigned at dev time, `com.apple.security.cs.disable-library-validation`, already present for Sparkle). Note in findings whether `allow-jit` must be added.

- [ ] **Step 4: Record findings** — write `apps/macos/Bogi/sidecar/PACKAGING.md`:

```markdown
# Sidecar packaging findings (spike B0)

- Node runtime: v22.11.0 darwin-arm64 (pinned).
- Embedded at: `Bogi.app/Contents/Resources/sidecar/node`.
- Sign: `codesign --force --options runtime --timestamp --sign "<Developer ID>" <node>`.
- Entitlements required: com.apple.security.cs.allow-jit (+ existing disable-library-validation).
- Launch: Process with executableURL = bundled node, arguments = [bundled main.cjs].
- Notarization: the embedded node is stapled as part of the .app submission.
```

- [ ] **Step 5: Commit the findings**

```bash
git add apps/macos/Bogi/sidecar/PACKAGING.md
git commit -m "spike(sidecar): pin Node runtime + document signing/entitlements"
```

## Task B1: Scaffold the sidecar TS project

**Files:**
- Create: `apps/macos/Bogi/sidecar/package.json`, `tsconfig.json`, `esbuild.mjs`, `vitest.config.ts`, `.gitignore`

- [ ] **Step 1: Create `apps/macos/Bogi/sidecar/package.json`**

```json
{
  "name": "bogi-sidecar",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "node esbuild.mjs",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "langchain": "^0.3.7",
    "@langchain/core": "^0.3.18",
    "@langchain/langgraph": "^0.2.20",
    "better-sqlite3": "^11.5.0",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "esbuild": "^0.24.0",
    "typescript": "^5.6.0",
    "vitest": "^2.1.0",
    "@types/better-sqlite3": "^7.6.11",
    "@types/node": "^22.9.0"
  }
}
```

- [ ] **Step 2: Create `apps/macos/Bogi/sidecar/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "types": ["node"],
    "outDir": "dist"
  },
  "include": ["src", "test"]
}
```

- [ ] **Step 3: Create `apps/macos/Bogi/sidecar/esbuild.mjs`**

`better-sqlite3` is a native module, so it must stay external and be shipped alongside the bundle. Output CJS so the embedded node can load it without ESM resolution quirks.

```javascript
import { build } from "esbuild";

await build({
  entryPoints: ["src/main.ts"],
  bundle: true,
  platform: "node",
  target: "node22",
  format: "cjs",
  outfile: "dist/main.cjs",
  external: ["better-sqlite3"],
});
console.log("sidecar bundled -> dist/main.cjs");
```

- [ ] **Step 4: Create `apps/macos/Bogi/sidecar/vitest.config.ts`**

```typescript
import { defineConfig } from "vitest/config";
export default defineConfig({ test: { environment: "node", include: ["test/**/*.test.ts"] } });
```

- [ ] **Step 5: Create `apps/macos/Bogi/sidecar/.gitignore`**

```
node_modules
dist
```

- [ ] **Step 6: Install and verify**

Run: `cd apps/macos/Bogi/sidecar && npm install && npm run typecheck`
Expected: install succeeds; `tsc --noEmit` exits 0 (no source files yet, so no type errors).

- [ ] **Step 7: Commit**

```bash
git add apps/macos/Bogi/sidecar/package.json apps/macos/Bogi/sidecar/tsconfig.json apps/macos/Bogi/sidecar/esbuild.mjs apps/macos/Bogi/sidecar/vitest.config.ts apps/macos/Bogi/sidecar/.gitignore apps/macos/Bogi/sidecar/package-lock.json
git commit -m "chore(sidecar): scaffold LangChain.js sidecar project"
```

## Task B2: Line-delimited JSON-RPC framing

**Files:**
- Create: `apps/macos/Bogi/sidecar/src/rpc.ts`
- Test: `apps/macos/Bogi/sidecar/test/rpc.test.ts`

The wire format is one JSON object per line (`\n`-delimited). Message kinds:
`{ kind: "chat", id, threadId, text }`, `{ kind: "plan", id, threadId, text }`,
`{ kind: "nudge_tick", id, threadId, payload }`, `{ kind: "action_result", id, ok, result }`
(inbound); `{ kind: "token", id, text }`, `{ kind: "result", id, ok, text }`,
`{ kind: "action_call", id, name, input }`, `{ kind: "error", id, message }`, `{ kind: "ready" }`
(outbound).

- [ ] **Step 1: Write the failing test** — create `test/rpc.test.ts`:

```typescript
import { test, expect } from "vitest";
import { LineDecoder, encodeMessage } from "../src/rpc.js";

test("encodeMessage produces one JSON line", () => {
  expect(encodeMessage({ kind: "ready" })).toBe('{"kind":"ready"}\n');
});

test("LineDecoder emits complete messages across chunk boundaries", () => {
  const got: any[] = [];
  const d = new LineDecoder((m) => got.push(m));
  d.push('{"kind":"chat","id":"1","tex');
  d.push('t":"hi","threadId":"t"}\n{"kind":"action_result","id":"2","ok":true}\n');
  expect(got).toEqual([
    { kind: "chat", id: "1", text: "hi", threadId: "t" },
    { kind: "action_result", id: "2", ok: true },
  ]);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: FAIL — cannot resolve `../src/rpc.js`.

- [ ] **Step 3: Implement `src/rpc.ts`**

```typescript
export type Inbound =
  | { kind: "chat"; id: string; threadId: string; text: string }
  | { kind: "plan"; id: string; threadId: string; text: string }
  | { kind: "nudge_tick"; id: string; threadId: string; payload: unknown }
  | { kind: "action_result"; id: string; ok: boolean; result?: unknown; message?: string };

export type Outbound =
  | { kind: "ready" }
  | { kind: "token"; id: string; text: string }
  | { kind: "result"; id: string; ok: boolean; text: string }
  | { kind: "action_call"; id: string; callId: string; name: string; input: unknown }
  | { kind: "error"; id: string; message: string };

export function encodeMessage(msg: Outbound): string {
  return JSON.stringify(msg) + "\n";
}

export class LineDecoder {
  private buf = "";
  constructor(private onMessage: (msg: Inbound) => void) {}
  push(chunk: string): void {
    this.buf += chunk;
    let nl: number;
    while ((nl = this.buf.indexOf("\n")) >= 0) {
      const line = this.buf.slice(0, nl).trim();
      this.buf = this.buf.slice(nl + 1);
      if (line) this.onMessage(JSON.parse(line) as Inbound);
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/rpc.ts apps/macos/Bogi/sidecar/test/rpc.test.ts
git commit -m "feat(sidecar): line-delimited JSON-RPC framing"
```

## Task B3: `BogiProxyChatModel` (LangChain model over `/v1/infer`)

**Files:**
- Create: `apps/macos/Bogi/sidecar/src/proxyChatModel.ts`
- Test: `apps/macos/Bogi/sidecar/test/proxyChatModel.test.ts`

This is a custom chat model extending `BaseChatModel` from `@langchain/core`. It converts LangChain messages + bound tools into our `/v1/infer` request shape (Task A6) and converts the response (`content` blocks with `tool_use`) back into an `AIMessage` with `tool_calls`. The HTTP function is injected so tests need no network.

- [ ] **Step 1: Write the failing test** — create `test/proxyChatModel.test.ts`:

```typescript
import { test, expect } from "vitest";
import { HumanMessage } from "@langchain/core/messages";
import { BogiProxyChatModel } from "../src/proxyChatModel.js";

test("maps a tool_use response into AIMessage.tool_calls", async () => {
  const calls: any[] = [];
  const model = new BogiProxyChatModel({
    post: async (body) => {
      calls.push(body);
      return {
        text: "",
        stopReason: "tool_use",
        content: [{ type: "tool_use", id: "t1", name: "search_activity", input: { keywords: "x" } }],
      };
    },
  });
  const res = await model.invoke([new HumanMessage("what did I do?")]);
  expect(res.tool_calls?.[0]).toMatchObject({ id: "t1", name: "search_activity", args: { keywords: "x" } });
  expect(calls[0].messages[0]).toMatchObject({ role: "user" });
});

test("maps a plain text response into AIMessage content", async () => {
  const model = new BogiProxyChatModel({
    post: async () => ({ text: "you focused 2h", stopReason: "end_turn", content: [{ type: "text", text: "you focused 2h" }] }),
  });
  const res = await model.invoke([new HumanMessage("summary")]);
  expect(res.content).toBe("you focused 2h");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: FAIL — cannot resolve `../src/proxyChatModel.js`.

- [ ] **Step 3: Implement `src/proxyChatModel.ts`**

```typescript
import { BaseChatModel, type BaseChatModelParams } from "@langchain/core/language_models/chat_models";
import { AIMessage, type BaseMessage } from "@langchain/core/messages";
import { ChatResult } from "@langchain/core/outputs";
import { type StructuredToolInterface } from "@langchain/core/tools";
import { zodToJsonSchema } from "zod/v4"; // if unavailable, use "zod-to-json-schema"

type InferBlock =
  | { type: "text"; text: string }
  | { type: "tool_use"; id: string; name: string; input: unknown }
  | { type: "tool_result"; tool_use_id: string; content: string };

interface InferResponse { text: string; content: InferBlock[]; stopReason: string }
interface InferRequest {
  system?: string;
  messages: { role: string; content: string | InferBlock[] }[];
  tools?: { name: string; description: string; input_schema: unknown }[];
  maxTokens?: number;
}

export interface BogiProxyChatModelFields extends BaseChatModelParams {
  post: (body: InferRequest) => Promise<InferResponse>;
  system?: string;
  maxTokens?: number;
}

function toInferMessages(messages: BaseMessage[]): InferRequest["messages"] {
  return messages.map((m) => {
    const role = m.getType() === "human" ? "user" : m.getType() === "ai" ? "assistant" : "user";
    if (m.getType() === "tool") {
      const tm = m as unknown as { tool_call_id: string; content: string };
      return { role: "user", content: [{ type: "tool_result", tool_use_id: tm.tool_call_id, content: String(tm.content) }] };
    }
    if (m.getType() === "ai") {
      const ai = m as AIMessage;
      if (ai.tool_calls?.length) {
        return {
          role: "assistant",
          content: ai.tool_calls.map((tc) => ({ type: "tool_use" as const, id: tc.id!, name: tc.name, input: tc.args })),
        };
      }
    }
    return { role, content: String(m.content) };
  });
}

export class BogiProxyChatModel extends BaseChatModel {
  private post: BogiProxyChatModelFields["post"];
  private system?: string;
  private maxTokens: number;
  private boundTools: InferRequest["tools"] = [];

  constructor(fields: BogiProxyChatModelFields) {
    super(fields);
    this.post = fields.post;
    this.system = fields.system;
    this.maxTokens = fields.maxTokens ?? 1024;
  }

  _llmType(): string { return "bogi-proxy"; }

  override bindTools(tools: StructuredToolInterface[]) {
    this.boundTools = tools.map((t) => ({
      name: t.name,
      description: t.description,
      input_schema: zodToJsonSchema(t.schema as any),
    }));
    return this;
  }

  async _generate(messages: BaseMessage[]): Promise<ChatResult> {
    const res = await this.post({
      system: this.system,
      messages: toInferMessages(messages),
      tools: this.boundTools?.length ? this.boundTools : undefined,
      maxTokens: this.maxTokens,
    });
    const text = res.content.filter((b) => b.type === "text").map((b) => (b as any).text).join("");
    const toolCalls = res.content
      .filter((b) => b.type === "tool_use")
      .map((b) => ({ id: (b as any).id, name: (b as any).name, args: (b as any).input, type: "tool_call" as const }));
    const message = new AIMessage({ content: text, tool_calls: toolCalls });
    return { generations: [{ text, message }] };
  }
}
```

Note: if `zod/v4`'s `zodToJsonSchema` import path is unavailable in the installed versions, add `zod-to-json-schema` to `dependencies` and import from there. Verify the exact `bindTools` / `tool_calls` shape against the installed `@langchain/core` during Step 4 and adjust the import only.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: PASS. If the zod-to-json-schema import errors, switch to `zod-to-json-schema` and re-run.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/proxyChatModel.ts apps/macos/Bogi/sidecar/test/proxyChatModel.test.ts apps/macos/Bogi/sidecar/package.json apps/macos/Bogi/sidecar/package-lock.json
git commit -m "feat(sidecar): BogiProxyChatModel bridging LangChain to /v1/infer"
```

## Task B4: Persona + agent factory (with one echo tool)

**Files:**
- Create: `apps/macos/Bogi/sidecar/src/persona.ts`, `apps/macos/Bogi/sidecar/src/agent.ts`
- Test: `apps/macos/Bogi/sidecar/test/agent.test.ts`

- [ ] **Step 1: Create the persona** — `src/persona.ts`:

```typescript
export const PERSONA = `You are Bogi, a warm and supportive accountability coach.

Rules:
- Speak directly TO the user (use "you"). Never write as if you were the user.
- Be kind and encouraging. Acknowledge effort and progress before pointing out gaps.
  Stay honest: surface gaps between plans and reality clearly, but gently, as next steps,
  never as failures, and never harshly.
- Ground every claim strictly in tool results. Do not invent numbers, activities, or goals.
- To answer questions about what the user did, call the data tools with keywords and time
  ranges. If the tools return nothing, say "I don't have data on that yet." Do not guess.
- Be concise. Lead with the answer, then the supporting evidence.
- Never use em-dashes. Use commas, periods, or parentheses instead.`;
```

- [ ] **Step 2: Write the failing test** — `test/agent.test.ts`:

```typescript
import { test, expect } from "vitest";
import { tool } from "@langchain/core/tools";
import { z } from "zod";
import { createBogiAgent } from "../src/agent.js";

test("agent invokes a tool then answers", async () => {
  const echo = tool(async ({ value }) => `echo:${value}`, {
    name: "echo", description: "Echo the value back.",
    schema: z.object({ value: z.string() }),
  });
  // Fake proxy: first turn asks for the tool, second turn answers with the tool output.
  let turn = 0;
  const agent = createBogiAgent({
    tools: [echo],
    post: async (body) => {
      turn += 1;
      if (turn === 1) {
        return { text: "", stopReason: "tool_use",
          content: [{ type: "tool_use", id: "t1", name: "echo", input: { value: "hi" } }] };
      }
      const toolMsg = JSON.stringify(body.messages.at(-1));
      return { text: `done ${toolMsg.includes("echo:hi") ? "ok" : "no"}`, stopReason: "end_turn",
        content: [{ type: "text", text: `done ${toolMsg.includes("echo:hi") ? "ok" : "no"}` }] };
    },
  });
  const res = await agent.invoke({ messages: [{ role: "user", content: "say hi" }] });
  expect(res.messages.at(-1)?.content).toContain("done ok");
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: FAIL — cannot resolve `../src/agent.js`.

- [ ] **Step 4: Implement `src/agent.ts`**

```typescript
import { createAgent } from "langchain";
import { MemorySaver } from "@langchain/langgraph";
import { type StructuredToolInterface } from "@langchain/core/tools";
import { BogiProxyChatModel, type BogiProxyChatModelFields } from "./proxyChatModel.js";
import { PERSONA } from "./persona.js";

export interface BogiAgentFields {
  tools: StructuredToolInterface[];
  post: BogiProxyChatModelFields["post"];
}

export function createBogiAgent(fields: BogiAgentFields) {
  const model = new BogiProxyChatModel({ post: fields.post, system: PERSONA });
  return createAgent({
    model,
    tools: fields.tools,
    systemPrompt: PERSONA,
    checkpointer: new MemorySaver(),
  });
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: PASS. If `createAgent`'s import path differs in the installed `langchain` version, confirm with `node -e "console.log(Object.keys(require('langchain')))"` and adjust the import.

- [ ] **Step 6: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/persona.ts apps/macos/Bogi/sidecar/src/agent.ts apps/macos/Bogi/sidecar/test/agent.test.ts
git commit -m "feat(sidecar): Bogi agent factory + unified persona"
```

## Task B5: stdio entrypoint

**Files:**
- Create: `apps/macos/Bogi/sidecar/src/main.ts`
- Test: `apps/macos/Bogi/sidecar/test/main.test.ts`

The entrypoint reads config from `argv`/env (backend base URL, auth token, db path — supplied later), wires the proxy `post`, decodes inbound lines, runs the agent per `chat`, and writes a `result`. Action tools are added in Phases D/E; for now register read tools as empty and wire just chat. To keep it testable, factor the dispatch into `handleMessage`.

- [ ] **Step 1: Write the failing test** — `test/main.test.ts`:

```typescript
import { test, expect } from "vitest";
import { makeDispatcher } from "../src/main.js";

test("chat message produces a result line", async () => {
  const out: string[] = [];
  const dispatch = makeDispatcher({
    agent: { invoke: async () => ({ messages: [{ content: "you did great" }] }) } as any,
    write: (line) => out.push(line),
  });
  await dispatch({ kind: "chat", id: "1", threadId: "t1", text: "how was today?" });
  expect(out.join("")).toContain('"kind":"result"');
  expect(out.join("")).toContain("you did great");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: FAIL — cannot resolve `../src/main.js`.

- [ ] **Step 3: Implement `src/main.ts`**

```typescript
import { LineDecoder, encodeMessage, type Inbound } from "./rpc.js";

interface AgentLike { invoke(input: unknown, config?: unknown): Promise<{ messages: { content: unknown }[] }> }

export function makeDispatcher(deps: { agent: AgentLike; write: (line: string) => void }) {
  return async function dispatch(msg: Inbound): Promise<void> {
    if (msg.kind === "chat" || msg.kind === "plan") {
      try {
        const res = await deps.agent.invoke(
          { messages: [{ role: "user", content: msg.text }] },
          { configurable: { thread_id: msg.threadId }, recursionLimit: 12 }
        );
        const text = String(res.messages.at(-1)?.content ?? "");
        deps.write(encodeMessage({ kind: "result", id: msg.id, ok: true, text }));
      } catch (err) {
        deps.write(encodeMessage({ kind: "error", id: msg.id, message: String((err as Error)?.message ?? err) }));
      }
    }
  };
}

// Real wiring (not exercised by unit tests): build proxy + agent from env, pump stdin.
export async function runStdio(): Promise<void> {
  const { createBogiAgent } = await import("./agent.js");
  const baseURL = process.env.BOGI_BACKEND_URL!;
  const token = process.env.BOGI_AUTH_TOKEN ?? "";
  const post = async (body: unknown) => {
    const r = await fetch(`${baseURL}/v1/infer`, {
      method: "POST",
      headers: { "content-type": "application/json", "X-Bogi-Authorization": `Bearer ${token}` },
      body: JSON.stringify(body),
    });
    return (await r.json()) as any;
  };
  const agent = createBogiAgent({ tools: [], post });
  const dispatch = makeDispatcher({ agent, write: (l) => process.stdout.write(l) });
  const decoder = new LineDecoder((m) => { void dispatch(m); });
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (c) => decoder.push(c as string));
  process.stdout.write(encodeMessage({ kind: "ready" }));
}

if (process.env.NODE_ENV !== "test") {
  // Only auto-run when launched as the bundled binary.
  if (process.argv[1]?.endsWith("main.cjs") || process.argv[1]?.endsWith("main.js")) {
    void runStdio();
  }
}
```

- [ ] **Step 4: Run test + build to verify**

Run: `cd apps/macos/Bogi/sidecar && npm test && npm run build`
Expected: tests PASS; `dist/main.cjs` is produced.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/main.ts apps/macos/Bogi/sidecar/test/main.test.ts
git commit -m "feat(sidecar): stdio entrypoint + chat dispatcher"
```

## Task B6: Swift SidecarClient + transport

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarTransport.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarClient.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/SidecarClientTests.swift`

`SidecarClient` depends on a `SidecarTransport` protocol so tests inject a fake. The real `ProcessSidecarTransport` launches the bundled node + `main.cjs`. The client correlates requests by `id` and resolves a continuation when a `result`/`error` line arrives.

- [ ] **Step 1: Create the transport protocol + process impl** — `SidecarTransport.swift`:

```swift
import Foundation

/// Bidirectional newline-delimited transport to the sidecar. Injectable for tests.
protocol SidecarTransport: AnyObject {
    var onLine: ((String) -> Void)? { get set }
    func send(_ line: String)
    func start() throws
    func stop()
}

/// Launches the bundled Node sidecar and pipes stdio.
final class ProcessSidecarTransport: SidecarTransport {
    var onLine: ((String) -> Void)?
    private let nodeURL: URL
    private let scriptURL: URL
    private let environment: [String: String]
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private var buffer = Data()

    init(nodeURL: URL, scriptURL: URL, environment: [String: String]) {
        self.nodeURL = nodeURL
        self.scriptURL = scriptURL
        self.environment = environment
    }

    func start() throws {
        process.executableURL = nodeURL
        process.arguments = [scriptURL.path]
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let self else { return }
            self.buffer.append(h.availableData)
            while let nl = self.buffer.firstIndex(of: 0x0A) {
                let lineData = self.buffer.subdata(in: self.buffer.startIndex..<nl)
                self.buffer.removeSubrange(self.buffer.startIndex...nl)
                if let line = String(data: lineData, encoding: .utf8) { self.onLine?(line) }
            }
        }
        try process.run()
    }

    func send(_ line: String) {
        stdinPipe.fileHandleForWriting.write(Data(line.utf8))
    }

    func stop() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }
}
```

- [ ] **Step 2: Write the failing test** — `SidecarClientTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class FakeTransport: SidecarTransport {
    var onLine: ((String) -> Void)?
    private(set) var sent: [String] = []
    var autoReply: ((String) -> String?)?
    func start() throws {}
    func stop() {}
    func send(_ line: String) {
        sent.append(line)
        if let reply = autoReply?(line) { onLine?(reply) }
    }
}

final class SidecarClientTests: XCTestCase {
    func testChatResolvesWithResultText() async throws {
        let transport = FakeTransport()
        transport.autoReply = { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String else { return nil }
            return #"{"kind":"result","id":"\#(id)","ok":true,"text":"you focused 2h"}"#
        }
        let client = SidecarClient(transport: transport)
        try client.start()
        let answer = try await client.chat("how was today?", threadId: "t1")
        XCTAssertEqual(answer, "you focused 2h")
        XCTAssertTrue(transport.sent.first?.contains("\"kind\":\"chat\"") == true)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/macos/Bogi && swift test --filter SidecarClientTests`
Expected: FAIL — no `SidecarClient` type.

- [ ] **Step 4: Implement `SidecarClient.swift`**

```swift
import Foundation

/// Correlates request ids to continuations and decodes sidecar result/error lines.
/// Action calls (Phases D/E) are handled via `actionHandler`, set by the app.
final class SidecarClient {
    private let transport: SidecarTransport
    private var pending: [String: CheckedContinuation<String, Error>] = [:]
    private var counter = 0
    private let lock = NSLock()
    /// Returns a JSON-encodable result for an action call (name, input) -> result.
    var actionHandler: ((_ name: String, _ input: [String: Any]) async -> [String: Any])?

    init(transport: SidecarTransport) {
        self.transport = transport
        self.transport.onLine = { [weak self] line in self?.handle(line) }
    }

    func start() throws { try transport.start() }
    func stop() { transport.stop() }

    private func nextId() -> String {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        return "req-\(counter)"
    }

    func chat(_ text: String, threadId: String) async throws -> String {
        try await request(kind: "chat", threadId: threadId, text: text)
    }

    func plan(_ text: String, threadId: String) async throws -> String {
        try await request(kind: "plan", threadId: threadId, text: text)
    }

    private func request(kind: String, threadId: String, text: String) async throws -> String {
        let id = nextId()
        let payload: [String: Any] = ["kind": kind, "id": id, "threadId": threadId, "text": text]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let line = String(data: data, encoding: .utf8)! + "\n"
        return try await withCheckedThrowingContinuation { cont in
            lock.lock(); pending[id] = cont; lock.unlock()
            transport.send(line)
        }
    }

    private func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = obj["kind"] as? String else { return }
        switch kind {
        case "result":
            guard let id = obj["id"] as? String else { return }
            resolve(id, .success((obj["text"] as? String) ?? ""))
        case "error":
            guard let id = obj["id"] as? String else { return }
            resolve(id, .failure(SidecarError.remote((obj["message"] as? String) ?? "sidecar error")))
        case "action_call":
            handleAction(obj)
        default:
            break
        }
    }

    private func handleAction(_ obj: [String: Any]) {
        guard let id = obj["id"] as? String, let callId = obj["callId"] as? String,
              let name = obj["name"] as? String else { return }
        let input = (obj["input"] as? [String: Any]) ?? [:]
        Task {
            let result = await actionHandler?(name, input) ?? ["ok": false, "error": "no handler"]
            let payload: [String: Any] = ["kind": "action_result", "id": id, "callId": callId,
                                          "ok": true, "result": result]
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let s = String(data: data, encoding: .utf8) { transport.send(s + "\n") }
        }
    }

    private func resolve(_ id: String, _ result: Result<String, Error>) {
        lock.lock(); let cont = pending.removeValue(forKey: id); lock.unlock()
        switch result {
        case .success(let s): cont?.resume(returning: s)
        case .failure(let e): cont?.resume(throwing: e)
        }
    }
}

enum SidecarError: Error { case remote(String) }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/macos/Bogi && swift test --filter SidecarClientTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarTransport.swift apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarClient.swift apps/macos/Bogi/Tests/BogiAppTests/SidecarClientTests.swift
git commit -m "feat(app): SidecarClient + process transport with id correlation"
```

## Task B7: Bundle node + sidecar into the .app

**Files:**
- Modify: `apps/macos/Bogi/Packaging/build-app.sh`
- Modify: `apps/macos/Bogi/Packaging/Bogi.entitlements` (if B0 found `allow-jit` needed)

- [ ] **Step 1: Add the JIT entitlement (if B0 required it)** — in `Bogi.entitlements`, add inside the top-level `<dict>`:

```xml
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
```

- [ ] **Step 2: Add a sidecar build+embed step to `build-app.sh`** — after the app binary is assembled into `RESOURCES="$APP/Contents/Resources"` and before the codesign step, insert:

```bash
# --- Sidecar (Node + LangChain.js agent) ---
SIDECAR_SRC="$ROOT/apps/macos/Bogi/sidecar"
SIDECAR_DST="$RESOURCES/sidecar"
NODE_VERSION="v22.11.0"
NODE_PKG="node-${NODE_VERSION}-darwin-arm64"

echo "Building sidecar bundle..."
( cd "$SIDECAR_SRC" && npm ci && npm run build )

mkdir -p "$SIDECAR_DST"
cp "$SIDECAR_SRC/dist/main.cjs" "$SIDECAR_DST/main.cjs"
# Ship the native better-sqlite3 module next to the bundle.
cp -R "$SIDECAR_SRC/node_modules/better-sqlite3" "$SIDECAR_DST/better-sqlite3"

# Embed the pinned Node runtime.
if [ ! -x "$SIDECAR_DST/node" ]; then
  curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${NODE_PKG}.tar.gz" -o /tmp/${NODE_PKG}.tar.gz
  tar xzf /tmp/${NODE_PKG}.tar.gz -C /tmp
  cp "/tmp/${NODE_PKG}/bin/node" "$SIDECAR_DST/node"
fi
```

- [ ] **Step 3: Sign the embedded node + native module before the app signature** — in the codesign section, before signing the outer `.app`, add deep-signing of nested executables:

```bash
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$RESOURCES/sidecar/node"
find "$RESOURCES/sidecar/better-sqlite3" -name "*.node" -print0 | \
  while IFS= read -r -d '' f; do
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$f"
  done
```

(`$SIGN_ID` and `$ROOT`/`$APP` should already exist in the script; reuse the existing variable names — read the current script and match them.)

- [ ] **Step 4: Verify the bundle builds + signs**

Run: `cd apps/macos/Bogi && bash Packaging/build-app.sh` (or the script's documented invocation). 
Expected: `Bogi.app/Contents/Resources/sidecar/{node,main.cjs,better-sqlite3}` exist; `codesign --verify --deep --strict Bogi.app` passes.

If you cannot run a full signed build in this environment, at minimum run the sidecar build (`cd apps/macos/Bogi/sidecar && npm ci && npm run build`) and confirm `dist/main.cjs` exists, and review the script edits for correctness.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Packaging/build-app.sh apps/macos/Bogi/Packaging/Bogi.entitlements
git commit -m "build(app): embed + sign Node sidecar in the app bundle"
```

---

# PHASE C — Read tools + Coach migration

## Task C1: Read-only SQLite access in the sidecar

**Files:**
- Create: `apps/macos/Bogi/sidecar/src/db.ts`
- Test: `apps/macos/Bogi/sidecar/test/db.test.ts`

- [ ] **Step 1: Write the failing test** — `test/db.test.ts`:

```typescript
import { test, expect } from "vitest";
import Database from "better-sqlite3";
import { openReadOnly } from "../src/db.js";

test("openReadOnly can query but not write", () => {
  const path = `/tmp/bogi-db-${process.pid}.sqlite`;
  const seed = new Database(path);
  seed.exec("CREATE TABLE t (x INTEGER); INSERT INTO t VALUES (1);");
  seed.close();

  const db = openReadOnly(path);
  expect(db.prepare("SELECT x FROM t").get()).toEqual({ x: 1 });
  expect(() => db.prepare("INSERT INTO t VALUES (2)").run()).toThrow();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: FAIL — cannot resolve `../src/db.js`.

- [ ] **Step 3: Implement `src/db.ts`**

```typescript
import Database from "better-sqlite3";

export type DB = Database.Database;

/** Open the app's SQLite file read-only. WAL lets us read without blocking the writer. */
export function openReadOnly(path: string): DB {
  const db = new Database(path, { readonly: true, fileMustExist: true });
  db.pragma("query_only = true");
  return db;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/db.ts apps/macos/Bogi/sidecar/test/db.test.ts
git commit -m "feat(sidecar): read-only SQLite open"
```

## Task C2: Read tools (search/summarize/list_days/list_goals)

**Files:**
- Create: `apps/macos/Bogi/sidecar/src/tools/readTools.ts`
- Test: `apps/macos/Bogi/sidecar/test/readTools.test.ts`

These query `activity_segments` (kept indefinitely), `planned_blocks`, `goals`, and `segment_fts`. Times are ISO-8601 strings compared against the `start_at` columns (GRDB stores datetimes as ISO text).

- [ ] **Step 1: Write the failing test** — `test/readTools.test.ts`:

```typescript
import { test, expect, beforeAll } from "vitest";
import Database from "better-sqlite3";
import { openReadOnly } from "../src/db.js";
import { makeReadTools } from "../src/tools/readTools.js";

const path = `/tmp/bogi-readtools-${process.pid}.sqlite`;

beforeAll(() => {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE activity_segments (id TEXT PRIMARY KEY, start_at TEXT, end_at TEXT, minutes REAL,
      planned_block_id TEXT, category TEXT, sub_category TEXT, sub_sub TEXT, on_task INTEGER,
      confidence REAL, judged_at TEXT);
    CREATE TABLE planned_blocks (id TEXT PRIMARY KEY, source TEXT, external_event_id TEXT, title TEXT,
      start_at TEXT, end_at TEXT, category TEXT, goal_id TEXT, status TEXT, created_by_bogi INTEGER, updated_at TEXT);
    CREATE TABLE goals (id TEXT PRIMARY KEY, title TEXT, period TEXT, target TEXT, created_at TEXT);
    CREATE VIRTUAL TABLE segment_fts USING fts5(segment_id UNINDEXED, description);
    INSERT INTO activity_segments VALUES
      ('s1','2026-06-01T09:00:00Z','2026-06-01T09:30:00Z',30,NULL,'Work','Coding','Editing video pipeline',1,0.9,'2026-06-01T09:30:00Z'),
      ('s2','2026-06-01T10:00:00Z','2026-06-01T10:20:00Z',20,NULL,'Distraction','Social','Scrolling X',0,0.8,'2026-06-01T10:20:00Z'),
      ('s3','2026-06-02T09:00:00Z','2026-06-02T09:40:00Z',40,NULL,'Work','Coding','Editing video pipeline',1,0.9,'2026-06-02T09:40:00Z');
    INSERT INTO segment_fts VALUES ('s1','Editing video pipeline'),('s2','Scrolling X'),('s3','Editing video pipeline');
    INSERT INTO goals VALUES ('g1','Ship Bogi','quarter','beta by July','2026-05-01T00:00:00Z');
  `);
  db.close();
});

test("search_activity filters by keyword + time range", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const search = tools.find((t) => t.name === "search_activity")!;
  const out = JSON.parse(await search.invoke({ keywords: "video", start: "2026-06-01T00:00:00Z", end: "2026-06-01T23:59:59Z" }));
  expect(out.results.length).toBe(1);
  expect(out.results[0].description).toContain("video pipeline");
});

test("summarize_range aggregates on/off task + categories", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const summarize = tools.find((t) => t.name === "summarize_range")!;
  const out = JSON.parse(await summarize.invoke({ start: "2026-06-01T00:00:00Z", end: "2026-06-01T23:59:59Z" }));
  expect(out.totalMinutes).toBe(50);
  expect(out.onTaskMinutes).toBe(30);
  expect(out.topCategories[0].category).toBe("Work");
});

test("list_days returns per-day totals", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const listDays = tools.find((t) => t.name === "list_days")!;
  const out = JSON.parse(await listDays.invoke({ start: "2026-06-01T00:00:00Z", end: "2026-06-02T23:59:59Z" }));
  expect(out.days.length).toBe(2);
  expect(out.days.find((d: any) => d.date === "2026-06-02").onTaskMinutes).toBe(40);
});

test("list_goals returns active goals", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const listGoals = tools.find((t) => t.name === "list_goals")!;
  const out = JSON.parse(await listGoals.invoke({}));
  expect(out.goals[0].title).toBe("Ship Bogi");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: FAIL — cannot resolve `../src/tools/readTools.js`.

- [ ] **Step 3: Implement `src/tools/readTools.ts`**

```typescript
import { tool } from "@langchain/core/tools";
import { z } from "zod";
import { type DB } from "../db.js";

type OpenDB = () => DB;

function ftsExpr(keywords: string): string {
  const toks = keywords.split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  return toks.map((t) => `"${t}"`).join(" OR ");
}

export function makeReadTools(open: OpenDB) {
  const search_activity = tool(
    async ({ keywords, start, end, limit }) => {
      const db = open();
      try {
        const rows = db.prepare(
          `SELECT s.start_at AS start_at, s.category AS category, s.on_task AS on_task, f.description AS description
             FROM segment_fts f JOIN activity_segments s ON s.id = f.segment_id
            WHERE segment_fts MATCH ?
              AND (? IS NULL OR s.start_at >= ?)
              AND (? IS NULL OR s.start_at <= ?)
            ORDER BY s.start_at DESC LIMIT ?`
        ).all(ftsExpr(keywords), start ?? null, start ?? null, end ?? null, end ?? null, limit ?? 20);
        return JSON.stringify({ results: rows });
      } finally { db.close(); }
    },
    {
      name: "search_activity",
      description: "Search the user's recorded activity by keywords, optionally within a time range. Returns matching activity descriptions with their time and on-task status.",
      schema: z.object({
        keywords: z.string().describe("Space-separated keywords, e.g. 'video editing'"),
        start: z.string().nullish().describe("ISO-8601 start of range, or omit"),
        end: z.string().nullish().describe("ISO-8601 end of range, or omit"),
        limit: z.number().int().positive().nullish().describe("Max results (default 20)"),
      }),
    }
  );

  const summarize_range = tool(
    async ({ start, end }) => {
      const db = open();
      try {
        const segs = db.prepare(
          `SELECT minutes, category, on_task FROM activity_segments WHERE start_at >= ? AND start_at <= ?`
        ).all(start, end) as { minutes: number; category: string | null; on_task: number | null }[];
        const totalMinutes = segs.reduce((a, s) => a + s.minutes, 0);
        const onTaskMinutes = segs.filter((s) => s.on_task === 1).reduce((a, s) => a + s.minutes, 0);
        const byCat = new Map<string, number>();
        for (const s of segs) byCat.set(s.category ?? "uncategorized", (byCat.get(s.category ?? "uncategorized") ?? 0) + s.minutes);
        const topCategories = [...byCat.entries()]
          .map(([category, minutes]) => ({ category, minutes }))
          .sort((a, b) => b.minutes - a.minutes).slice(0, 8);
        const blocks = db.prepare(
          `SELECT title, start_at, end_at FROM planned_blocks WHERE start_at >= ? AND start_at <= ? ORDER BY start_at`
        ).all(start, end);
        return JSON.stringify({ totalMinutes, onTaskMinutes, offTaskMinutes: totalMinutes - onTaskMinutes, topCategories, plannedBlocks: blocks });
      } finally { db.close(); }
    },
    {
      name: "summarize_range",
      description: "Summarize the user's tracked time in a date range: total minutes, on-task vs off-task, top categories, and the calendar blocks they planned.",
      schema: z.object({
        start: z.string().describe("ISO-8601 start of range"),
        end: z.string().describe("ISO-8601 end of range"),
      }),
    }
  );

  const list_days = tool(
    async ({ start, end }) => {
      const db = open();
      try {
        const rows = db.prepare(
          `SELECT substr(start_at,1,10) AS date,
                  SUM(minutes) AS totalMinutes,
                  SUM(CASE WHEN on_task = 1 THEN minutes ELSE 0 END) AS onTaskMinutes
             FROM activity_segments WHERE start_at >= ? AND start_at <= ?
            GROUP BY date ORDER BY date`
        ).all(start, end);
        return JSON.stringify({ days: rows });
      } finally { db.close(); }
    },
    {
      name: "list_days",
      description: "List per-day total and on-task minutes across a date range. Use for trend questions like 'which day last week was most productive'.",
      schema: z.object({
        start: z.string().describe("ISO-8601 start of range"),
        end: z.string().describe("ISO-8601 end of range"),
      }),
    }
  );

  const list_goals = tool(
    async () => {
      const db = open();
      try {
        const rows = db.prepare(`SELECT title, period, target FROM goals ORDER BY created_at`).all();
        return JSON.stringify({ goals: rows });
      } finally { db.close(); }
    },
    {
      name: "list_goals",
      description: "List the user's active goals and their targets so you can reason about progress.",
      schema: z.object({}),
    }
  );

  return [search_activity, summarize_range, list_days, list_goals];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: PASS — 4 read-tool tests.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/tools/readTools.ts apps/macos/Bogi/sidecar/test/readTools.test.ts
git commit -m "feat(sidecar): read tools over local SQLite (keyword + time range)"
```

## Task C3: Register read tools + pass DB path through

**Files:**
- Modify: `apps/macos/Bogi/sidecar/src/main.ts` (`runStdio`)

- [ ] **Step 1: Wire the tools into `runStdio`** — update the agent construction:

```typescript
  const { createBogiAgent } = await import("./agent.js");
  const { makeReadTools } = await import("./tools/readTools.js");
  const { openReadOnly } = await import("./db.js");
  const dbPath = process.env.BOGI_DB_PATH!;
  const tools = makeReadTools(() => openReadOnly(dbPath));
  // ... existing post ...
  const agent = createBogiAgent({ tools, post });
```

- [ ] **Step 2: Verify build + existing tests still pass**

Run: `cd apps/macos/Bogi/sidecar && npm test && npm run build`
Expected: PASS; bundle builds. (No new unit test here; `runStdio` is integration-only and covered by the smoke in Task C5.)

- [ ] **Step 3: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/main.ts
git commit -m "feat(sidecar): register read tools and accept DB path via env"
```

## Task C4: Route Coach through the sidecar

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Coach/CoachService.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/CoachTests.swift` (create if absent)

The Coach no longer pre-builds today-only context or calls `InferenceClient` directly; it forwards the question to the sidecar (which queries the data bank via tools). To stay testable, introduce a small `CoachBackend` protocol that `SidecarClient` satisfies.

- [ ] **Step 1: Write the failing test** — create `CoachTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class FakeCoachBackend: CoachBackend {
    var lastText: String?
    var lastThread: String?
    func chat(_ text: String, threadId: String) async throws -> String {
        lastText = text; lastThread = threadId
        return "Nice work, you focused two hours today."
    }
}

final class CoachTests: XCTestCase {
    func testAskForwardsToBackend() async throws {
        let backend = FakeCoachBackend()
        let coach = CoachService(backend: backend, threadId: "coach-1")
        let answer = try await coach.ask("how was today?")
        XCTAssertEqual(answer, "Nice work, you focused two hours today.")
        XCTAssertEqual(backend.lastText, "how was today?")
        XCTAssertEqual(backend.lastThread, "coach-1")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi && swift test --filter CoachTests`
Expected: FAIL — `CoachBackend` and the new `CoachService` initializer do not exist.

- [ ] **Step 3: Rewrite `CoachService.swift`** to the slim form:

```swift
import Foundation

/// Forwards a question to the on-device agent, which queries the data bank via tools.
protocol CoachBackend {
    func chat(_ text: String, threadId: String) async throws -> String
}

extension SidecarClient: CoachBackend {}

/// The accountability coach. Persona, grounding, and data access now live in the agent
/// (sidecar); this type just carries the question to it on a stable conversation thread.
final class CoachService {
    private let backend: CoachBackend
    private let threadId: String

    init(backend: CoachBackend, threadId: String = "coach") {
        self.backend = backend
        self.threadId = threadId
    }

    func ask(_ question: String) async throws -> String {
        try await backend.chat(question, threadId: threadId)
    }
}
```

This removes the old `systemPrompt`, `buildContext`, `retrieveSnippets`, and the dependencies on `InsightsService`/`SearchService`/`GoalsService` from the Coach. If any test (e.g. an existing `CoachTests` or a `buildContext` test) references those removed members, delete those obsolete tests in this step — their behavior now lives in the sidecar read tools (Task C2).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos/Bogi && swift test --filter CoachTests`
Expected: PASS.

- [ ] **Step 5: Update the call site** — in `AppDelegate.swift`, find where `CoachService(...)` is constructed and the `CoachView` ask closure is wired. Replace the construction with the sidecar-backed coach:

```swift
        let coach = CoachService(backend: sidecarClient, threadId: "coach")
```

where `sidecarClient` is the `SidecarClient` built during app startup (Task C6). Remove now-unused `insights`/`search`/`goals` arguments previously passed to `CoachService`.

- [ ] **Step 6: Build to verify wiring**

Run: `cd apps/macos/Bogi && swift build`
Expected: builds (after Task C6 provides `sidecarClient`; if doing C4 before C6, temporarily construct a `SidecarClient` with a `ProcessSidecarTransport` stub or reorder to do C6 first).

- [ ] **Step 7: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Coach/CoachService.swift apps/macos/Bogi/Tests/BogiAppTests/CoachTests.swift apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift
git commit -m "feat(coach): route Coach questions through the on-device agent"
```

## Task C5: App startup wiring + smoke

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift`

- [ ] **Step 1: Build + launch the sidecar at startup** — in `AppDelegate` startup, after the DB and backend config are available, add:

```swift
        // On-device agent sidecar.
        let resources = Bundle.main.resourceURL!.appendingPathComponent("sidecar")
        let env: [String: String] = [
            "BOGI_BACKEND_URL": backendBaseURL.absoluteString,
            "BOGI_AUTH_TOKEN": (try? authTokenProvider()) ?? "",
            "BOGI_DB_PATH": databaseFileURL.path,
            "NODE_PATH": resources.appendingPathComponent("better-sqlite3/..").path,
        ]
        let transport = ProcessSidecarTransport(
            nodeURL: resources.appendingPathComponent("node"),
            scriptURL: resources.appendingPathComponent("main.cjs"),
            environment: env)
        let sidecarClient = SidecarClient(transport: transport)
        try? sidecarClient.start()
```

Use the existing names in `AppDelegate` for the backend base URL, the Supabase token provider, and the on-disk SQLite file path (read the file to find them; e.g. `BackendConfig`, `DatabaseService` file URL). `NODE_PATH` must point at the directory that contains `better-sqlite3` so `require("better-sqlite3")` resolves next to `main.cjs`.

- [ ] **Step 2: Manual smoke** — build and run the app (see `run` skill / `Packaging/build-app.sh`), open the Coach chat, ask "what did I do yesterday?".
Expected: a grounded, kind, em-dash-free reply that reflects real segments (or "I don't have data on that yet" if empty). In Console, the sidecar process is alive and `/v1/infer` is called with a `tools` array.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift
git commit -m "feat(app): launch agent sidecar at startup and back the Coach with it"
```

---

# PHASE D — Planner via action tools

## Task D1: Action-call round trip in the sidecar

**Files:**
- Create: `apps/macos/Bogi/sidecar/src/tools/actionTools.ts`
- Modify: `apps/macos/Bogi/sidecar/src/main.ts`
- Test: `apps/macos/Bogi/sidecar/test/actionTools.test.ts`

Action tools cannot run in Node (they need EventKit / app UI). Each emits an `action_call` to Swift and awaits the matching `action_result`. We model this with an injected `callAction(name, input)` function so it is unit-testable; `runStdio` provides the real one backed by the RPC channel.

- [ ] **Step 1: Write the failing test** — `test/actionTools.test.ts`:

```typescript
import { test, expect } from "vitest";
import { makeActionTools } from "../src/tools/actionTools.js";

test("create_block emits an action call and returns its result", async () => {
  const seen: any[] = [];
  const tools = makeActionTools(async (name, input) => { seen.push({ name, input }); return { ok: true, id: "blk1" }; });
  const create = tools.find((t) => t.name === "create_block")!;
  const out = JSON.parse(await create.invoke({ title: "Edit video", start: "2026-06-07T15:00:00Z", end: "2026-06-07T16:00:00Z" }));
  expect(out).toEqual({ ok: true, id: "blk1" });
  expect(seen[0].name).toBe("create_block");
  expect(seen[0].input.title).toBe("Edit video");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: FAIL — cannot resolve `../src/tools/actionTools.js`.

- [ ] **Step 3: Implement `src/tools/actionTools.ts`**

```typescript
import { tool } from "@langchain/core/tools";
import { z } from "zod";

export type CallAction = (name: string, input: unknown) => Promise<unknown>;

export function makeActionTools(callAction: CallAction) {
  const create_block = tool(
    async (input) => JSON.stringify(await callAction("create_block", input)),
    {
      name: "create_block",
      description: "Create a planned calendar block of focused time. Resolve relative dates/times against the current time before calling.",
      schema: z.object({
        title: z.string().describe("Activity name"),
        start: z.string().describe("ISO-8601 start datetime"),
        end: z.string().describe("ISO-8601 end datetime"),
      }),
    }
  );

  const move_block = tool(
    async (input) => JSON.stringify(await callAction("move_block", input)),
    {
      name: "move_block",
      description: "Move an existing planned block to a new time. Identify it by a title fragment.",
      schema: z.object({
        match: z.string().describe("A fragment of the block title to move"),
        start: z.string().describe("New ISO-8601 start datetime"),
        end: z.string().describe("New ISO-8601 end datetime"),
      }),
    }
  );

  return [create_block, move_block];
}
```

- [ ] **Step 4: Wire action plumbing in `runStdio`** — in `main.ts`, add a pending-action registry and a `callAction` that emits `action_call` and resolves on `action_result`. Replace the `decoder` wiring:

```typescript
  const { makeActionTools } = await import("./tools/actionTools.js");
  const pendingActions = new Map<string, (result: unknown) => void>();
  let actionSeq = 0;
  const callAction = (name: string, input: unknown) =>
    new Promise((resolve) => {
      const callId = `act-${++actionSeq}`;
      pendingActions.set(callId, resolve);
      process.stdout.write(JSON.stringify({ kind: "action_call", id: "agent", callId, name, input }) + "\n");
    });

  const tools = [...makeReadTools(() => openReadOnly(dbPath)), ...makeActionTools(callAction)];
  const agent = createBogiAgent({ tools, post });
  const dispatch = makeDispatcher({ agent, write: (l) => process.stdout.write(l) });
  const decoder = new LineDecoder((m) => {
    if (m.kind === "action_result") { pendingActions.get((m as any).callId)?.((m as any).result); pendingActions.delete((m as any).callId); return; }
    void dispatch(m);
  });
```

- [ ] **Step 5: Run tests + build to verify**

Run: `cd apps/macos/Bogi/sidecar && npm test && npm run build`
Expected: PASS; bundle builds.

- [ ] **Step 6: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/tools/actionTools.ts apps/macos/Bogi/sidecar/src/main.ts apps/macos/Bogi/sidecar/test/actionTools.test.ts
git commit -m "feat(sidecar): create_block/move_block action tools + RPC round trip"
```

## Task D2: Swift action handlers

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarActionHandlers.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/SidecarActionHandlerTests.swift`

- [ ] **Step 1: Write the failing test** — `SidecarActionHandlerTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class SidecarActionHandlerTests: XCTestCase {
    func testCreateBlockHandlerParsesAndDelegates() async {
        var created: (String, Date, Date)?
        let handlers = SidecarActionHandlers(
            createBlock: { title, start, end in created = (title, start, end); return "blk-1" },
            moveBlock: { _, _, _ in nil })
        let iso = ISO8601DateFormatter()
        let input: [String: Any] = [
            "title": "Edit video",
            "start": "2026-06-07T15:00:00Z",
            "end": "2026-06-07T16:00:00Z",
        ]
        let result = await handlers.handle("create_block", input)
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(result["id"] as? String, "blk-1")
        XCTAssertEqual(created?.0, "Edit video")
        XCTAssertEqual(created?.1, iso.date(from: "2026-06-07T15:00:00Z"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi && swift test --filter SidecarActionHandlerTests`
Expected: FAIL — no `SidecarActionHandlers`.

- [ ] **Step 3: Implement `SidecarActionHandlers.swift`**

```swift
import Foundation

/// Executes agent action calls that only the app can perform (calendar writes, nudges).
/// Pure routing + parsing; the actual side effects are injected closures so this is testable.
final class SidecarActionHandlers {
    typealias CreateBlock = (_ title: String, _ start: Date, _ end: Date) async -> String?
    typealias MoveBlock = (_ match: String, _ start: Date, _ end: Date) async -> String?

    private let createBlock: CreateBlock
    private let moveBlock: MoveBlock
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    init(createBlock: @escaping CreateBlock, moveBlock: @escaping MoveBlock) {
        self.createBlock = createBlock
        self.moveBlock = moveBlock
    }

    /// Returns a JSON-encodable dictionary result for the given action.
    func handle(_ name: String, _ input: [String: Any]) async -> [String: Any] {
        switch name {
        case "create_block":
            guard let title = input["title"] as? String,
                  let start = date(input["start"]), let end = date(input["end"]) else {
                return ["ok": false, "error": "bad_input"]
            }
            if let id = await createBlock(title, start, end) { return ["ok": true, "id": id] }
            return ["ok": false, "error": "create_failed"]
        case "move_block":
            guard let match = input["match"] as? String,
                  let start = date(input["start"]), let end = date(input["end"]) else {
                return ["ok": false, "error": "bad_input"]
            }
            if let id = await moveBlock(match, start, end) { return ["ok": true, "id": id] }
            return ["ok": false, "error": "not_found"]
        default:
            return ["ok": false, "error": "unknown_action"]
        }
    }

    private func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        return iso.date(from: s)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos/Bogi && swift test --filter SidecarActionHandlerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarActionHandlers.swift apps/macos/Bogi/Tests/BogiAppTests/SidecarActionHandlerTests.swift
git commit -m "feat(app): sidecar action handlers for calendar writes"
```

## Task D3: Connect handlers + route the Planner through the agent

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift`
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Planner/PlannerService.swift`

- [ ] **Step 1: Wire the action handler into the sidecar client** — in `AppDelegate` after building `sidecarClient`, connect calendar actions to the existing `PlannedBlockRepository`/`PlannerService`:

```swift
        let actions = SidecarActionHandlers(
            createBlock: { title, start, end in
                await plannedBlocks.create(title: title, start: start, end: end)?.id
            },
            moveBlock: { match, start, end in
                await plannedBlocks.move(matching: match, start: start, end: end)?.id
            })
        sidecarClient.actionHandler = { name, input in await actions.handle(name, input) }
```

Use the real method names on the existing planner/repository (read `PlannerService.swift` and `PlannedBlockRepository.swift`). If those methods are synchronous or have different signatures, adapt the closures to call them (wrapping in `await MainActor.run { ... }` as needed). The point: `create_block` → create a planned block; `move_block` → move one.

- [ ] **Step 2: Route the voice/text planner command to the agent** — in `PlannerService.swift`, replace the `PlannerCommandParser`-based path so an utterance is sent to `sidecarClient.plan(utterance, threadId: "planner")`. The agent now calls `create_block`/`move_block` itself. Keep `PlannerCommandParser` only if other code still references it; otherwise remove its usage here.

Concretely, change the method that currently does `parser.parse(...)` then applies the command, to:

```swift
    func handle(utterance: String) async throws {
        _ = try await sidecar.plan(utterance, threadId: "planner")
        // The agent performs create_block/move_block via action tools; nothing else to do.
    }
```

where `sidecar` is a `SidecarClient` injected into `PlannerService`. Add it to the initializer and update the `AppDelegate` construction accordingly.

- [ ] **Step 3: Build + run smoke**

Run: `cd apps/macos/Bogi && swift build`, then run the app and say/enter "schedule one hour to edit video tomorrow at 3pm".
Expected: a planned block appears in the calendar for tomorrow 15:00–16:00, and the agent confirms in prose.

- [ ] **Step 4: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift apps/macos/Bogi/Sources/BogiApp/Features/Planner/PlannerService.swift
git commit -m "feat(planner): route planning through the agent's action tools"
```

---

# PHASE E — Nudge gate + agent-owned nudging

## Task E1: Remove the nudge instruction from segmentation

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgePrompt.swift:14-22`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/JudgeTests.swift`

The segmentation call now only segments; nudging belongs to the agent. The strict-JSON output still includes a `nudge` object for backward compatibility (so `JudgeOutput` parsing is unchanged), but the prompt is reframed as segmentation-only and tells the model to always set `should=false`.

- [ ] **Step 1: Write the failing test** — append to `JudgeTests.swift`:

```swift
func testSegmentationPromptIsSegmentationOnly() {
    XCTAssertTrue(JudgePrompt.system.contains("segmenter"),
                  "prompt should describe a segmenter, not a nudger")
    XCTAssertFalse(JudgePrompt.system.lowercased().contains("preachy"),
                   "old nudge-wording should be gone")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi && swift test --filter JudgeTests/testSegmentationPromptIsSegmentationOnly`
Expected: FAIL — the current prompt says "activity judge" and "never preachy".

- [ ] **Step 3: Rewrite `JudgePrompt.system`**

```swift
    static let system = """
    You are Bogi's activity segmenter. You receive ~5 minutes of a user's on-screen activity \
    (the focused window is marked) and the calendar block they planned. Return STRICT JSON only. \
    1) Segment activity into time segments each labeled category, sub_category, sub_sub \
    (short concrete description) with minutes. \
    2) Judge on_task: does the dominant activity match the planned block's intent? \
    Always set the should field of the nudge object to false; that decision is made elsewhere. \
    Never use em-dashes.
    """
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/macos/Bogi && swift test --filter JudgeTests`
Expected: PASS. Existing judge parse/run tests still work because `JudgeOutput` still has a `nudge` field (the model now always returns `should=false`).

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgePrompt.swift apps/macos/Bogi/Tests/BogiAppTests/JudgeTests.swift
git commit -m "refactor(judge): segmentation prompt no longer decides nudges"
```

## Task E2: Nudge gate heuristic

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Judge/NudgeGate.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/NudgeGateTests.swift`

- [ ] **Step 1: Write the failing test** — `NudgeGateTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class NudgeGateTests: XCTestCase {
    func testGateOpensWhenOffTaskExceedsThreshold() {
        let gate = NudgeGate(offTaskMinutesThreshold: 3)
        let segs = [
            JudgeSegment(startAt: Date(), endAt: Date(), minutes: 2, category: "Distraction",
                         subCategory: nil, subSub: nil, onTask: false, confidence: 0.9),
            JudgeSegment(startAt: Date(), endAt: Date(), minutes: 2, category: "Distraction",
                         subCategory: nil, subSub: nil, onTask: false, confidence: 0.9),
        ]
        XCTAssertTrue(gate.shouldConsiderNudge(segments: segs, hasActivePlan: true))
    }

    func testGateStaysClosedWhenOnTask() {
        let gate = NudgeGate(offTaskMinutesThreshold: 3)
        let segs = [JudgeSegment(startAt: Date(), endAt: Date(), minutes: 5, category: "Work",
                                 subCategory: nil, subSub: nil, onTask: true, confidence: 0.9)]
        XCTAssertFalse(gate.shouldConsiderNudge(segments: segs, hasActivePlan: true))
    }

    func testGateStaysClosedWithoutAPlan() {
        let gate = NudgeGate(offTaskMinutesThreshold: 0)
        let segs = [JudgeSegment(startAt: Date(), endAt: Date(), minutes: 9, category: "Distraction",
                                 subCategory: nil, subSub: nil, onTask: false, confidence: 0.9)]
        XCTAssertFalse(gate.shouldConsiderNudge(segments: segs, hasActivePlan: false))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi && swift test --filter NudgeGateTests`
Expected: FAIL — no `NudgeGate`.

- [ ] **Step 3: Implement `NudgeGate.swift`**

```swift
import Foundation

/// Cheap, deterministic pre-check run every 5-minute tick. Only when it opens do we pay for
/// an agent invocation to decide and word a nudge. Keeps the background path cheap.
struct NudgeGate {
    let offTaskMinutesThreshold: Double

    init(offTaskMinutesThreshold: Double = 3) {
        self.offTaskMinutesThreshold = offTaskMinutesThreshold
    }

    func shouldConsiderNudge(segments: [JudgeSegment], hasActivePlan: Bool) -> Bool {
        guard hasActivePlan else { return false }
        let offTask = segments.filter { $0.onTask == false }.reduce(0) { $0 + $1.minutes }
        return offTask > offTaskMinutesThreshold
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos/Bogi && swift test --filter NudgeGateTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Judge/NudgeGate.swift apps/macos/Bogi/Tests/BogiAppTests/NudgeGateTests.swift
git commit -m "feat(judge): cheap nudge gate heuristic"
```

## Task E3: `post_nudge` action tool

**Files:**
- Modify: `apps/macos/Bogi/sidecar/src/tools/actionTools.ts`
- Modify: `apps/macos/Bogi/sidecar/test/actionTools.test.ts`

- [ ] **Step 1: Add the failing test** — append to `test/actionTools.test.ts`:

```typescript
test("post_nudge emits an action call", async () => {
  const seen: any[] = [];
  const tools = makeActionTools(async (name, input) => { seen.push({ name, input }); return { ok: true }; });
  const nudge = tools.find((t) => t.name === "post_nudge")!;
  const out = JSON.parse(await nudge.invoke({ severity: 2, message: "Gently, you drifted to X. Want to refocus?" }));
  expect(out).toEqual({ ok: true });
  expect(seen[0].name).toBe("post_nudge");
  expect(seen[0].input.severity).toBe(2);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: FAIL — no `post_nudge` tool.

- [ ] **Step 3: Add the tool** — in `makeActionTools`, before the `return`:

```typescript
  const post_nudge = tool(
    async (input) => JSON.stringify(await callAction("post_nudge", input)),
    {
      name: "post_nudge",
      description: "Show the user a short, kind, supportive nudge when they have drifted off their planned focus. Be specific and honest about the drift but gentle and encouraging. Never use em-dashes.",
      schema: z.object({
        severity: z.number().int().min(0).max(3).describe("0 gentle .. 3 urgent"),
        message: z.string().describe("The nudge text shown above the mascot"),
      }),
    }
  );

  return [create_block, move_block, post_nudge];
```

- [ ] **Step 4: Run test + build to verify**

Run: `cd apps/macos/Bogi/sidecar && npm test && npm run build`
Expected: PASS; bundle builds.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/tools/actionTools.ts apps/macos/Bogi/sidecar/test/actionTools.test.ts
git commit -m "feat(sidecar): post_nudge action tool"
```

## Task E4: Coordinator gates then delegates nudging to the agent

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeService.swift`
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeCoordinator.swift`
- Modify: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarActionHandlers.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/JudgeTests.swift`

The flow becomes: segmentation (`runOnce`) returns segments → `NudgeGate` checks them → if open, build a compact summary and send `nudge_tick` to the sidecar on an ephemeral thread → the agent may call `post_nudge`, which routes to a Swift handler that presents the mascot nudge.

- [ ] **Step 1: Expose segments from `JudgeService.runOnce`** — change the return type to also surface the segments the gate needs. Add a result struct:

```swift
struct JudgeRun {
    let segments: [JudgeSegment]
    let nudge: JudgeNudge   // retained for compatibility; should is always false now
}
```

and update `runOnce` to `-> JudgeRun` returning `JudgeRun(segments: output.segments, nudge: output.nudge)` (it already builds `output`). Update the existing judge tests that read `output.nudge`/the return value accordingly (they call `service.runOnce(input:)` and check `nudge.should`; change them to read `.nudge.should` on the new struct, or `.segments`).

- [ ] **Step 2: Add a `post_nudge` handler** — in `SidecarActionHandlers`, add a third closure:

```swift
    typealias PostNudge = (_ severity: Int, _ message: String) async -> Void
    // add to init and stored properties; in handle():
        case "post_nudge":
            guard let message = input["message"] as? String else { return ["ok": false, "error": "bad_input"] }
            let severity = (input["severity"] as? Int) ?? 0
            await postNudge(severity, message)
            return ["ok": true]
```

Update the initializer signature and the `AppDelegate` construction to pass a `postNudge` closure that calls the existing `NudgePresenter`/mascot presentation (read `NudgePresenter.swift`):

```swift
            postNudge: { severity, message in
                _ = presenter.present(message: message, now: Date())
            })
```

- [ ] **Step 3: Gate + delegate in `JudgeCoordinator.tick`** — inject a `NudgeGate` and the `SidecarClient`, and replace the tail of `tick()`:

```swift
        guard let run = try? await judge.runOnce(input: input) else { return }
        let onTask = !nudgeGate.shouldConsiderNudge(segments: run.segments, hasActivePlan: active != nil)
        onResult(NudgeDecision(show: false, escalationLevel: 0, playSound: false, text: nil), onTask)
        guard nudgeGate.shouldConsiderNudge(segments: run.segments, hasActivePlan: active != nil) else { return }

        let summary = Self.nudgeSummary(active: active, segments: run.segments, now: now)
        _ = try? await sidecar.plan(summary, threadId: "nudge")   // ephemeral thread; agent may call post_nudge
```

Add the constructor params (`nudgeGate: NudgeGate`, `sidecar: SidecarClient`) and a small pure helper:

```swift
    static func nudgeSummary(active: PlannedBlock?, segments: [JudgeSegment], now: Date) -> String {
        let off = segments.filter { $0.onTask == false }
            .map { $0.subSub ?? $0.subCategory ?? $0.category ?? "something else" }
        let plan = active?.title ?? "no specific plan"
        return "In the last 5 minutes the user planned '\(plan)' but spent time on: " +
               off.joined(separator: ", ") +
               ". If this is a real drift, call post_nudge with a kind, supportive message. Otherwise do nothing."
    }
```

(Use the real `PlannedBlock` type name from `PlannedBlockRepository.swift`. The `nudge_tick` kind exists in the protocol, but reusing `plan` keeps one agent code path; the prompt content tells the agent to call `post_nudge`. If you prefer the dedicated `nudge_tick` kind, add a `nudgeTick` method on `SidecarClient` mirroring `plan` and a `dispatch` branch for it.)

- [ ] **Step 4: Update `AppDelegate` wiring** — pass the `NudgeGate()` and `sidecarClient` into `JudgeCoordinator(...)`.

- [ ] **Step 5: Run tests + build**

Run: `cd apps/macos/Bogi && swift test --filter JudgeTests && swift build`
Expected: PASS; builds.

- [ ] **Step 6: Manual smoke** — run the app with an active plan, then deliberately go off-task for several minutes.
Expected: after a tick, a kind, em-dash-free mascot nudge appears (only when off-task exceeds the threshold; staying on-task produces no nudge and no agent call).

- [ ] **Step 7: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeService.swift apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeCoordinator.swift apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarActionHandlers.swift apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift apps/macos/Bogi/Tests/BogiAppTests/JudgeTests.swift
git commit -m "feat(judge): gate ticks and let the agent decide + word nudges"
```

---

# Final verification

- [ ] **Backend:** `cd backend && node --test && npm run build` — all green.
- [ ] **Sidecar:** `cd apps/macos/Bogi/sidecar && npm test && npm run typecheck && npm run build` — all green.
- [ ] **App:** `cd apps/macos/Bogi && swift test` — all green.
- [ ] **End-to-end smoke** (signed build via `Packaging/build-app.sh`):
  - Coach: "what did I do last week?" returns grounded, kind, em-dash-free prose driven by `summarize_range`/`search_activity`.
  - Planner: "schedule 1h to edit video tomorrow at 3pm" creates the block.
  - Nudge: sustained off-task with an active plan yields a gentle mascot nudge; on-task yields none.
- [ ] Confirm raw observation text never appears in any outbound request body except as tool results the agent chose to send (inspect `/v1/infer` payloads in Console).
