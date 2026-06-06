import { LineDecoder, encodeMessage, type Inbound } from "./rpc.js";
import { type StreamFn, type StreamFrame } from "./proxyChatModel.js";

interface AgentLike {
  invoke(input: unknown, config?: unknown): Promise<{ messages: { content: unknown }[] }>;
  // Optional underlying model whose `activeRequestId` is set so streamed token frames
  // can be tagged with the id of the in-flight chat/plan/judge request.
  __bogiModel?: { activeRequestId: string | null };
}

export function makeDispatcher(deps: {
  agent: AgentLike;
  write: (line: string) => void;
  // Optional sink for a fresh per-request auth token. The transport closures
  // (WS connect / HTTP post) read this before each inference so a token that
  // rotated after launch is still used. No-op when omitted (tests).
  setToken?: (token: string | undefined) => void;
}) {
  return async function dispatch(msg: Inbound): Promise<void> {
    if (msg.kind === "chat" || msg.kind === "plan" || msg.kind === "judge") {
      try {
        deps.setToken?.(msg.token);
        if (deps.agent.__bogiModel) deps.agent.__bogiModel.activeRequestId = msg.id;
        const res = await deps.agent.invoke(
          { messages: [{ role: "user", content: msg.text }] },
          { configurable: { thread_id: msg.threadId }, recursionLimit: 12 }
        );
        const text = String(res.messages.at(-1)?.content ?? "");
        deps.write(encodeMessage({ kind: "result", id: msg.id, ok: true, text }));
      } catch (err) {
        deps.write(encodeMessage({ kind: "error", id: msg.id, message: String((err as Error)?.message ?? err) }));
      } finally {
        if (deps.agent.__bogiModel) deps.agent.__bogiModel.activeRequestId = null;
      }
    }
  };
}

// Build a streaming transport backed by a `ws` WebSocket. One connection per inference:
// connect to BOGI_WS_URL?token=..., send {action:"infer", ...}, yield parsed frames until
// stop/done/error. The token is resolved per-connection via `getToken` so a token that
// rotated after launch is honored. Not exercised by unit tests (the model uses an injected
// fake `stream`).
export function makeWsStream(wsUrl: string, getToken: () => string): StreamFn {
  return async function* (body): AsyncIterable<StreamFrame> {
    const { default: WebSocket } = await import("ws");
    const token = getToken();
    const sep = wsUrl.includes("?") ? "&" : "?";
    const ws = new WebSocket(`${wsUrl}${sep}token=${encodeURIComponent(token)}`);

    // Bridge ws events into an async queue we can iterate.
    const queue: StreamFrame[] = [];
    let resolveNext: (() => void) | null = null;
    let closed = false;
    let failure: Error | null = null;
    const wake = () => { resolveNext?.(); resolveNext = null; };
    const push = (f: StreamFrame) => { queue.push(f); wake(); };

    ws.on("message", (data: unknown) => {
      try { push(JSON.parse(String(data)) as StreamFrame); }
      catch { push({ type: "error", message: "bad_frame" }); }
    });
    ws.on("error", (err: Error) => { failure = err; closed = true; wake(); });
    ws.on("close", () => { closed = true; wake(); });

    await new Promise<void>((resolve, reject) => {
      ws.once("open", () => resolve());
      ws.once("error", (err: Error) => reject(err));
    });
    ws.send(JSON.stringify({
      action: "infer",
      system: body.system,
      messages: body.messages,
      tools: body.tools,
      maxTokens: body.maxTokens,
    }));

    try {
      while (true) {
        while (queue.length === 0 && !closed) {
          await new Promise<void>((r) => { resolveNext = r; });
        }
        if (failure) throw failure;
        if (queue.length === 0 && closed) break;
        const frame = queue.shift()!;
        yield frame;
        if (frame.type === "stop" || frame.type === "done" || frame.type === "error") break;
      }
    } finally {
      try { ws.close(); } catch { /* ignore */ }
    }
  };
}

// Real wiring (not exercised by unit tests): build proxy + agent from env, pump stdin.
export async function runStdio(): Promise<void> {
  const { createBogiAgent } = await import("./agent.js");
  const { makeReadTools } = await import("./tools/readTools.js");
  const { openReadOnly } = await import("./db.js");
  const dbPath = process.env.BOGI_DB_PATH!;
  const baseURL = process.env.BOGI_BACKEND_URL!;
  const envToken = process.env.BOGI_AUTH_TOKEN ?? "";
  // The auth token rotates ~hourly. The app threads a fresh token on each request
  // frame; `currentToken` holds the token for the in-flight dispatch (set by the
  // dispatcher's setToken before each agent.invoke), falling back to the env token
  // captured at launch.
  let currentToken = envToken;
  const getToken = () => currentToken || envToken;
  const post = async (body: unknown) => {
    const r = await fetch(`${baseURL}/v1/infer`, {
      method: "POST",
      headers: { "content-type": "application/json", "X-Bogi-Authorization": `Bearer ${getToken()}` },
      body: JSON.stringify(body),
    });
    const raw = await r.text();
    if (!r.ok) throw new Error(`backend ${r.status}: ${raw.slice(0, 300)}`);
    return JSON.parse(raw) as any;
  };
  const { makeActionTools } = await import("./tools/actionTools.js");
  const pendingActions = new Map<string, (result: unknown) => void>();
  let actionSeq = 0;
  const callAction = (name: string, input: unknown) =>
    new Promise((resolve) => {
      const callId = `act-${++actionSeq}`;
      pendingActions.set(callId, resolve);
      process.stdout.write(JSON.stringify({ kind: "action_call", id: "agent", callId, name, input }) + "\n");
    });

  const { makeRecordTools } = await import("./tools/recordTools.js");
  const tools = [
    ...makeReadTools(() => openReadOnly(dbPath)),
    ...makeActionTools(callAction),
    ...makeRecordTools(callAction),
  ];
  // When BOGI_WS_URL is set, stream model turns over a WebSocket and emit text deltas as
  // `token` RPC frames tagged with the id of the in-flight request (read off the model).
  // Otherwise fall back to the non-streaming HTTP `post`.
  const wsUrl = process.env.BOGI_WS_URL;
  let modelRef: { activeRequestId: string | null } | undefined;
  const onToken = wsUrl
    ? (text: string) => {
        const id = modelRef?.activeRequestId;
        if (id != null) process.stdout.write(encodeMessage({ kind: "token", id, text }));
      }
    : undefined;
  const stream = wsUrl ? makeWsStream(wsUrl, getToken) : undefined;

  const agent = createBogiAgent(wsUrl ? { tools, stream, onToken } : { tools, post });
  modelRef = (agent as unknown as { __bogiModel?: { activeRequestId: string | null } }).__bogiModel;
  const dispatch = makeDispatcher({
    agent,
    write: (l) => process.stdout.write(l),
    setToken: (t) => { currentToken = t ?? envToken; },
  });
  const decoder = new LineDecoder((m) => {
    if (m.kind === "action_result") { pendingActions.get((m as any).callId)?.((m as any).result); pendingActions.delete((m as any).callId); return; }
    void dispatch(m);
  });
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (c) => decoder.push(String(c)));
  process.stdout.write(encodeMessage({ kind: "ready" }));
}

if (process.env.NODE_ENV !== "test") {
  // Only auto-run when launched as the bundled binary.
  if (process.argv[1]?.endsWith("main.cjs") || process.argv[1]?.endsWith("main.js")) {
    void runStdio();
  }
}
