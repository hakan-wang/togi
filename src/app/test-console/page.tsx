"use client";

import { useMemo, useState } from "react";

type Method = "GET" | "POST" | "PATCH" | "DELETE";

type Result = {
  id: number;
  label: string;
  method: Method;
  path: string;
  status: string;
  elapsedMs: number;
  body: unknown;
};

const pretty = (value: unknown) => JSON.stringify(value, null, 2);

const defaultGoalCreate = pretty({
  title: "Test goal",
  description: "Created from the test console"
});

const defaultGoalPatch = pretty({
  status: "completed"
});

const defaultBlockCreate = pretty({
  title: "Write console smoke notes",
  startTime: "2026-06-06T09:00:00.000Z",
  endTime: "2026-06-06T10:00:00.000Z",
  intentionText: "Write concrete notes from the backend test console run",
  successCriteria: ["Create one backend smoke result", "Record any failing route"],
  category: "testing"
});

const defaultBlockPatch = pretty({
  status: "completed"
});

const defaultRealityCreate = pretty({
  plannedBlockId: "",
  actualSummary: "Created and checked the backend console flow.",
  completionScore: 0.9,
  deviationReason: "No major deviation.",
  actualCategories: ["testing"],
  confirmedByUser: true
});

const defaultRealityPatch = pretty({
  completionScore: 1
});

const defaultPlannerInput = pretty({
  request: "Plan one focused backend test block tomorrow",
  calendarAvailability: [{ startTime: "2026-06-06T09:00:00.000Z", endTime: "2026-06-06T10:00:00.000Z" }],
  activeGoals: [{ id: "goal-x", title: "Ship backend", status: "active" }],
  userPatterns: []
});

const defaultRealityAgentInput = pretty({
  plannedBlock: {
    id: "block-x",
    title: "Write notes",
    intentionText: "Write notes",
    successCriteria: ["Write notes", "Send notes"]
  },
  userAnswer: "I wrote notes but did not send notes.",
  historicalContext: []
});

const defaultCoachInput = pretty({
  question: "What should I plan next?"
});

const parseJson = (value: string) => {
  const trimmed = value.trim();
  return trimmed ? JSON.parse(trimmed) : undefined;
};

export default function TestConsolePage() {
  const [token, setToken] = useState("api-user");
  const [results, setResults] = useState<Result[]>([]);
  const [isRunningAll, setIsRunningAll] = useState(false);
  const [latestGoalId, setLatestGoalId] = useState("");
  const [latestBlockId, setLatestBlockId] = useState("");
  const [latestRealityLogId, setLatestRealityLogId] = useState("");
  const [goalCreate, setGoalCreate] = useState(defaultGoalCreate);
  const [goalPatch, setGoalPatch] = useState(defaultGoalPatch);
  const [blockCreate, setBlockCreate] = useState(defaultBlockCreate);
  const [blockPatch, setBlockPatch] = useState(defaultBlockPatch);
  const [realityCreate, setRealityCreate] = useState(defaultRealityCreate);
  const [realityPatch, setRealityPatch] = useState(defaultRealityPatch);
  const [plannerInput, setPlannerInput] = useState(defaultPlannerInput);
  const [realityAgentInput, setRealityAgentInput] = useState(defaultRealityAgentInput);
  const [coachInput, setCoachInput] = useState(defaultCoachInput);

  const authHeaders = useMemo(
    () => ({
      authorization: `Bearer ${token.trim() || "api-user"}`
    }),
    [token]
  );

  const recordResult = (result: Omit<Result, "id">) => {
    setResults((current) => [{ ...result, id: Date.now() + Math.random() }, ...current].slice(0, 40));
  };

  const callApi = async <T,>(label: string, method: Method, path: string, body?: unknown): Promise<T | null> => {
    const started = performance.now();

    try {
      const response = await fetch(path, {
        method,
        headers:
          body === undefined
            ? authHeaders
            : {
                ...authHeaders,
                "content-type": "application/json"
              },
        body: body === undefined ? undefined : JSON.stringify(body)
      });
      const text = await response.text();
      const responseBody = text ? JSON.parse(text) : null;

      recordResult({
        label,
        method,
        path,
        status: `${response.status} ${response.statusText}`,
        elapsedMs: Math.round(performance.now() - started),
        body: responseBody
      });

      return response.ok ? (responseBody as T) : null;
    } catch (error) {
      recordResult({
        label,
        method,
        path,
        status: "client error",
        elapsedMs: Math.round(performance.now() - started),
        body: { error: error instanceof Error ? error.message : "Unknown error" }
      });
      return null;
    }
  };

  const requireId = (label: string, id: string) => {
    if (id) return true;
    recordResult({
      label,
      method: "GET",
      path: "(missing id)",
      status: "not sent",
      elapsedMs: 0,
      body: { error: "Create or enter an id first." }
    });
    return false;
  };

  const createGoal = async () => {
    const goal = await callApi<{ id: string }>("Create goal", "POST", "/api/goals", parseJson(goalCreate));
    if (goal?.id) setLatestGoalId(goal.id);
  };

  const createBlock = async (body = parseJson(blockCreate)) => {
    const block = await callApi<{ id: string }>("Create planned block", "POST", "/api/planned-blocks", body);
    if (block?.id) {
      setLatestBlockId(block.id);
      setRealityCreate((current) => pretty({ ...parseJson(current), plannedBlockId: block.id }));
    }
    return block;
  };

  const createRealityLog = async () => {
    const body = { ...parseJson(realityCreate), plannedBlockId: latestBlockId || parseJson(realityCreate).plannedBlockId };
    const log = await callApi<{ id: string }>("Create reality log", "POST", "/api/reality-logs", body);
    if (log?.id) setLatestRealityLogId(log.id);
  };

  const runAll = async () => {
    setIsRunningAll(true);
    try {
      await callApi("Health", "GET", "/api/health");
      const goal = await callApi<{ id: string }>("Create goal", "POST", "/api/goals", parseJson(goalCreate));
      if (goal?.id) {
        setLatestGoalId(goal.id);
        await callApi("List goals", "GET", "/api/goals");
        await callApi("Patch goal", "PATCH", `/api/goals/${goal.id}`, parseJson(goalPatch));
      }

      const block = await createBlock();
      if (block?.id) {
        await callApi("List planned blocks", "GET", "/api/planned-blocks");
        await callApi("Get planned block", "GET", `/api/planned-blocks/${block.id}`);
        await callApi("Patch planned block", "PATCH", `/api/planned-blocks/${block.id}`, parseJson(blockPatch));
        const log = await callApi<{ id: string }>("Create reality log", "POST", "/api/reality-logs", {
          ...parseJson(realityCreate),
          plannedBlockId: block.id
        });
        if (log?.id) {
          setLatestRealityLogId(log.id);
          await callApi("List reality logs", "GET", "/api/reality-logs");
          await callApi("Get reality log", "GET", `/api/reality-logs/${log.id}`);
          await callApi("Patch reality log", "PATCH", `/api/reality-logs/${log.id}`, parseJson(realityPatch));
        }
      }

      const deleteBlock = await createBlock({
        ...parseJson(blockCreate),
        title: "Temporary delete check",
        startTime: "2026-06-06T11:00:00.000Z",
        endTime: "2026-06-06T12:00:00.000Z"
      });
      if (deleteBlock?.id) await callApi("Delete planned block", "DELETE", `/api/planned-blocks/${deleteBlock.id}`);

      await callApi("Planner agent", "POST", "/api/agents/planner", parseJson(plannerInput));
      await callApi("Reality-log agent", "POST", "/api/agents/reality-log", parseJson(realityAgentInput));
      await callApi("Coach agent", "POST", "/api/agents/coach", parseJson(coachInput));
      await callApi("Patterns", "GET", "/api/patterns");
      await callApi("Google Calendar connect", "GET", "/api/calendar/google/connect");
      await callApi("Google Calendar callback", "GET", "/api/calendar/google/callback?code=test-code");
      await callApi("Google Calendar sync", "POST", "/api/calendar/google/sync", {});
    } finally {
      setIsRunningAll(false);
    }
  };

  return (
    <main style={styles.page}>
      <header style={styles.header}>
        <div>
          <h1 style={styles.title}>Agent Backend Test Console</h1>
          <p style={styles.subtitle}>Run every implemented Togi backend route from one local page.</p>
        </div>
        <button style={styles.primaryButton} onClick={runAll} disabled={isRunningAll}>
          {isRunningAll ? "Running..." : "Run all smoke tests"}
        </button>
      </header>

      <section style={styles.toolbar}>
        <label style={styles.label}>
          Bearer token
          <input style={styles.input} value={token} onChange={(event) => setToken(event.target.value)} />
        </label>
        <Readout label="Latest goal" value={latestGoalId || "-"} />
        <Readout label="Latest block" value={latestBlockId || "-"} />
        <Readout label="Latest reality log" value={latestRealityLogId || "-"} />
      </section>

      <div style={styles.grid}>
        <Panel title="Health">
          <Action label="GET /api/health" onClick={() => callApi("Health", "GET", "/api/health")} />
        </Panel>

        <Panel title="Goals">
          <JsonEditor value={goalCreate} onChange={setGoalCreate} />
          <Action label="POST /api/goals" onClick={createGoal} />
          <Action label="GET /api/goals" onClick={() => callApi("List goals", "GET", "/api/goals")} />
          <JsonEditor value={goalPatch} onChange={setGoalPatch} />
          <Action
            label="PATCH /api/goals/:id"
            onClick={() =>
              requireId("Patch goal", latestGoalId) &&
              callApi("Patch goal", "PATCH", `/api/goals/${latestGoalId}`, parseJson(goalPatch))
            }
          />
        </Panel>

        <Panel title="Planned Blocks">
          <JsonEditor value={blockCreate} onChange={setBlockCreate} />
          <Action label="POST /api/planned-blocks" onClick={() => createBlock()} />
          <Action label="GET /api/planned-blocks" onClick={() => callApi("List planned blocks", "GET", "/api/planned-blocks")} />
          <JsonEditor value={blockPatch} onChange={setBlockPatch} />
          <Action
            label="GET /api/planned-blocks/:id"
            onClick={() =>
              requireId("Get planned block", latestBlockId) &&
              callApi("Get planned block", "GET", `/api/planned-blocks/${latestBlockId}`)
            }
          />
          <Action
            label="PATCH /api/planned-blocks/:id"
            onClick={() =>
              requireId("Patch planned block", latestBlockId) &&
              callApi("Patch planned block", "PATCH", `/api/planned-blocks/${latestBlockId}`, parseJson(blockPatch))
            }
          />
          <Action
            label="DELETE /api/planned-blocks/:id"
            onClick={() =>
              requireId("Delete planned block", latestBlockId) &&
              callApi("Delete planned block", "DELETE", `/api/planned-blocks/${latestBlockId}`)
            }
          />
        </Panel>

        <Panel title="Reality Logs">
          <JsonEditor value={realityCreate} onChange={setRealityCreate} />
          <Action label="POST /api/reality-logs" onClick={createRealityLog} />
          <Action label="GET /api/reality-logs" onClick={() => callApi("List reality logs", "GET", "/api/reality-logs")} />
          <JsonEditor value={realityPatch} onChange={setRealityPatch} />
          <Action
            label="GET /api/reality-logs/:id"
            onClick={() =>
              requireId("Get reality log", latestRealityLogId) &&
              callApi("Get reality log", "GET", `/api/reality-logs/${latestRealityLogId}`)
            }
          />
          <Action
            label="PATCH /api/reality-logs/:id"
            onClick={() =>
              requireId("Patch reality log", latestRealityLogId) &&
              callApi("Patch reality log", "PATCH", `/api/reality-logs/${latestRealityLogId}`, parseJson(realityPatch))
            }
          />
        </Panel>

        <Panel title="Agents">
          <h3 style={styles.smallHeading}>Planner</h3>
          <JsonEditor value={plannerInput} onChange={setPlannerInput} />
          <Action label="POST /api/agents/planner" onClick={() => callApi("Planner agent", "POST", "/api/agents/planner", parseJson(plannerInput))} />
          <h3 style={styles.smallHeading}>Reality Log</h3>
          <JsonEditor value={realityAgentInput} onChange={setRealityAgentInput} />
          <Action
            label="POST /api/agents/reality-log"
            onClick={() => callApi("Reality-log agent", "POST", "/api/agents/reality-log", parseJson(realityAgentInput))}
          />
          <h3 style={styles.smallHeading}>Coach</h3>
          <JsonEditor value={coachInput} onChange={setCoachInput} />
          <Action label="POST /api/agents/coach" onClick={() => callApi("Coach agent", "POST", "/api/agents/coach", parseJson(coachInput))} />
        </Panel>

        <Panel title="Patterns">
          <Action label="GET /api/patterns" onClick={() => callApi("Patterns", "GET", "/api/patterns")} />
        </Panel>

        <Panel title="Google Calendar">
          <Action label="GET /api/calendar/google/connect" onClick={() => callApi("Google Calendar connect", "GET", "/api/calendar/google/connect")} />
          <Action
            label="GET /api/calendar/google/callback?code=test-code"
            onClick={() => callApi("Google Calendar callback", "GET", "/api/calendar/google/callback?code=test-code")}
          />
          <Action label="POST /api/calendar/google/sync" onClick={() => callApi("Google Calendar sync", "POST", "/api/calendar/google/sync", {})} />
        </Panel>
      </div>

      <section style={styles.results}>
        <div style={styles.resultsHeader}>
          <h2 style={styles.sectionTitle}>Results</h2>
          <button style={styles.secondaryButton} onClick={() => setResults([])}>
            Clear
          </button>
        </div>
        {results.length === 0 ? (
          <p style={styles.empty}>No calls yet.</p>
        ) : (
          results.map((result) => (
            <article key={result.id} style={styles.result}>
              <div style={styles.resultMeta}>
                <strong>{result.label}</strong>
                <span>
                  {result.method} {result.path}
                </span>
                <span>{result.status}</span>
                <span>{result.elapsedMs}ms</span>
              </div>
              <pre style={styles.pre}>{pretty(result.body)}</pre>
            </article>
          ))
        )}
      </section>
    </main>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section style={styles.panel}>
      <h2 style={styles.sectionTitle}>{title}</h2>
      <div style={styles.stack}>{children}</div>
    </section>
  );
}

function Action({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button style={styles.button} onClick={onClick}>
      {label}
    </button>
  );
}

function JsonEditor({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  return <textarea style={styles.textarea} value={value} onChange={(event) => onChange(event.target.value)} spellCheck={false} />;
}

function Readout({ label, value }: { label: string; value: string }) {
  return (
    <div style={styles.readout}>
      <span>{label}</span>
      <code>{value}</code>
    </div>
  );
}

const styles = {
  page: {
    minHeight: "100vh",
    margin: 0,
    padding: 24,
    background: "#f6f7f9",
    color: "#18202a",
    fontFamily: "Arial, Helvetica, sans-serif"
  },
  header: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 16,
    marginBottom: 16
  },
  title: {
    margin: 0,
    fontSize: 28,
    lineHeight: 1.1
  },
  subtitle: {
    margin: "6px 0 0",
    color: "#526070"
  },
  toolbar: {
    display: "grid",
    gridTemplateColumns: "minmax(220px, 1fr) repeat(3, minmax(0, 1fr))",
    gap: 12,
    marginBottom: 16
  },
  label: {
    display: "grid",
    gap: 6,
    fontSize: 13,
    fontWeight: 700
  },
  input: {
    minHeight: 36,
    border: "1px solid #cbd3dc",
    borderRadius: 6,
    padding: "0 10px",
    fontSize: 14
  },
  readout: {
    display: "grid",
    gap: 6,
    minWidth: 0,
    padding: 10,
    border: "1px solid #d7dee6",
    borderRadius: 6,
    background: "#ffffff",
    fontSize: 13
  },
  grid: {
    display: "grid",
    gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))",
    gap: 14,
    alignItems: "start"
  },
  panel: {
    border: "1px solid #d7dee6",
    borderRadius: 8,
    padding: 14,
    background: "#ffffff"
  },
  sectionTitle: {
    margin: "0 0 10px",
    fontSize: 18,
    lineHeight: 1.2
  },
  smallHeading: {
    margin: "8px 0 0",
    fontSize: 14
  },
  stack: {
    display: "grid",
    gap: 8
  },
  button: {
    minHeight: 34,
    border: "1px solid #9facba",
    borderRadius: 6,
    background: "#eef2f6",
    color: "#18202a",
    fontWeight: 700,
    cursor: "pointer"
  },
  primaryButton: {
    minHeight: 40,
    border: "1px solid #165f7a",
    borderRadius: 6,
    background: "#18708f",
    color: "#ffffff",
    padding: "0 14px",
    fontWeight: 700,
    cursor: "pointer"
  },
  secondaryButton: {
    minHeight: 32,
    border: "1px solid #c2ccd6",
    borderRadius: 6,
    background: "#ffffff",
    color: "#18202a",
    padding: "0 12px",
    fontWeight: 700,
    cursor: "pointer"
  },
  textarea: {
    width: "100%",
    minHeight: 132,
    boxSizing: "border-box",
    border: "1px solid #cbd3dc",
    borderRadius: 6,
    padding: 10,
    fontSize: 12,
    lineHeight: 1.45,
    fontFamily: "Menlo, Consolas, monospace",
    resize: "vertical"
  },
  results: {
    marginTop: 16,
    border: "1px solid #d7dee6",
    borderRadius: 8,
    padding: 14,
    background: "#ffffff"
  },
  resultsHeader: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12
  },
  empty: {
    margin: 0,
    color: "#526070"
  },
  result: {
    borderTop: "1px solid #e3e8ee",
    paddingTop: 10,
    marginTop: 10
  },
  resultMeta: {
    display: "flex",
    flexWrap: "wrap",
    gap: 10,
    marginBottom: 8,
    fontSize: 13,
    color: "#3c4856"
  },
  pre: {
    overflow: "auto",
    maxHeight: 320,
    margin: 0,
    padding: 10,
    borderRadius: 6,
    background: "#101820",
    color: "#e7edf3",
    fontSize: 12,
    lineHeight: 1.45
  }
} satisfies Record<string, React.CSSProperties>;
