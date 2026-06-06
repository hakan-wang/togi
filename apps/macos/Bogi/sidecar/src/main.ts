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
  const { makeReadTools } = await import("./tools/readTools.js");
  const { openReadOnly } = await import("./db.js");
  const dbPath = process.env.BOGI_DB_PATH!;
  const baseURL = process.env.BOGI_BACKEND_URL!;
  const token = process.env.BOGI_AUTH_TOKEN ?? "";
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
