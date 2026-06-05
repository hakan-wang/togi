"use client";

import { FormEvent, useMemo, useState } from "react";

type Goal = {
  id: string;
  title: string;
  status: string;
};

type PlannedBlock = {
  id: string;
  title: string;
  startTime: string;
  endTime: string;
  intentionText: string;
  successCriteria: string[];
  category: string;
  status: string;
};

type RealityLog = {
  id: string;
  actualSummary: string;
  completionScore: number;
  deviationReason: string;
};

type RealityDraft = {
  actualSummary: string;
  completionScore: number;
  actualCategories: string[];
  deviationReason: string;
  clarificationQuestion: string | null;
  confirmedByUser: boolean;
};

type ChatResponse = {
  mode: "planner" | "reality_log" | "coach";
  assistantMessage: string;
  suggestions: string[];
  artifacts: {
    plannedBlocks: PlannedBlock[];
    realityDraft: RealityDraft | null;
  };
  state: {
    goals: Goal[];
    plannedBlocks: PlannedBlock[];
    realityLogs: RealityLog[];
  };
};

type Message = {
  id: number;
  role: "user" | "assistant";
  text: string;
  response?: ChatResponse;
};

const initialResponse: ChatResponse = {
  mode: "coach",
  assistantMessage: "Tell me what you want to get done, and I will turn it into a checkable plan.",
  suggestions: ["Plan my next focused block", "What should I do next?", "I finished my last block"],
  artifacts: {
    plannedBlocks: [],
    realityDraft: null
  },
  state: {
    goals: [],
    plannedBlocks: [],
    realityLogs: []
  }
};

const formatTime = (value: string) =>
  new Intl.DateTimeFormat("en", {
    hour: "numeric",
    minute: "2-digit"
  }).format(new Date(value));

export default function HomePage() {
  const [input, setInput] = useState("Plan one focused block for shipping the backend tomorrow morning");
  const [isSending, setIsSending] = useState(false);
  const [latestResponse, setLatestResponse] = useState<ChatResponse>(initialResponse);
  const [messages, setMessages] = useState<Message[]>([
    {
      id: 1,
      role: "assistant",
      text: initialResponse.assistantMessage,
      response: initialResponse
    }
  ]);

  const todayBlocks = useMemo(() => latestResponse.state.plannedBlocks.slice(-5).reverse(), [latestResponse.state.plannedBlocks]);
  const recentLogs = useMemo(() => latestResponse.state.realityLogs.slice(-4).reverse(), [latestResponse.state.realityLogs]);

  const sendMessage = async (text: string) => {
    const message = text.trim();
    if (!message || isSending) return;

    const userMessage: Message = { id: Date.now(), role: "user", text: message };
    setMessages((current) => [...current, userMessage]);
    setInput("");
    setIsSending(true);

    try {
      const response = await fetch("/api/chat", {
        method: "POST",
        headers: {
          authorization: "Bearer api-user",
          "content-type": "application/json"
        },
        body: JSON.stringify({ message })
      });
      const body = (await response.json()) as ChatResponse | { error: string };

      if (!response.ok || "error" in body) {
        throw new Error("error" in body ? body.error : "Togi could not answer.");
      }

      setLatestResponse(body);
      setMessages((current) => [
        ...current,
        {
          id: Date.now() + 1,
          role: "assistant",
          text: body.assistantMessage,
          response: body
        }
      ]);
    } catch (error) {
      setMessages((current) => [
        ...current,
        {
          id: Date.now() + 1,
          role: "assistant",
          text: error instanceof Error ? error.message : "Togi could not answer."
        }
      ]);
    } finally {
      setIsSending(false);
    }
  };

  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    void sendMessage(input);
  };

  return (
    <main style={styles.shell}>
      <section style={styles.chatColumn}>
        <header style={styles.topBar}>
          <div>
            <p style={styles.kicker}>Togi</p>
            <h1 style={styles.title}>Accountability coach</h1>
          </div>
          <div style={styles.status}>Live session</div>
        </header>

        <div style={styles.thread} aria-label="Conversation">
          {messages.map((message) => (
            <article key={message.id} style={message.role === "user" ? styles.userBubble : styles.assistantBubble}>
              <div style={styles.messageRole}>{message.role === "user" ? "You" : "Togi"}</div>
              <p style={styles.messageText}>{message.text}</p>
              {message.response?.artifacts.plannedBlocks.length ? <PlannedBlockSet blocks={message.response.artifacts.plannedBlocks} /> : null}
              {message.response?.artifacts.realityDraft ? <RealityDraftCard draft={message.response.artifacts.realityDraft} /> : null}
            </article>
          ))}
        </div>

        <div style={styles.suggestions}>
          {latestResponse.suggestions.map((suggestion) => (
            <button key={suggestion} style={styles.suggestionButton} onClick={() => void sendMessage(suggestion)}>
              {suggestion}
            </button>
          ))}
        </div>

        <form style={styles.composer} onSubmit={onSubmit}>
          <label style={styles.composerLabel}>
            Ask Togi
            <input
              style={styles.composerInput}
              value={input}
              onChange={(event) => setInput(event.target.value)}
              placeholder="Tell Togi what you want to plan or what actually happened"
            />
          </label>
          <button style={styles.sendButton} disabled={isSending}>
            {isSending ? "Thinking" : "Send"}
          </button>
        </form>
      </section>

      <aside style={styles.sideColumn}>
        <section style={styles.panel}>
          <h2 style={styles.panelTitle}>Today</h2>
          {todayBlocks.length === 0 ? (
            <p style={styles.muted}>No checkable blocks yet.</p>
          ) : (
            <div style={styles.itemList}>
              {todayBlocks.map((block) => (
                <article key={block.id} style={styles.item}>
                  <div style={styles.itemHeader}>
                    <strong>{block.title}</strong>
                    <span style={styles.badge}>{block.status}</span>
                  </div>
                  <p style={styles.muted}>
                    {formatTime(block.startTime)} - {formatTime(block.endTime)}
                  </p>
                  <p style={styles.itemText}>{block.intentionText}</p>
                </article>
              ))}
            </div>
          )}
        </section>

        <section style={styles.panel}>
          <h2 style={styles.panelTitle}>Goals</h2>
          {latestResponse.state.goals.length === 0 ? (
            <p style={styles.muted}>Add goals through chat when the backend supports it.</p>
          ) : (
            <div style={styles.itemList}>
              {latestResponse.state.goals.slice(-4).map((goal) => (
                <article key={goal.id} style={styles.item}>
                  <div style={styles.itemHeader}>
                    <strong>{goal.title}</strong>
                    <span style={styles.badge}>{goal.status}</span>
                  </div>
                </article>
              ))}
            </div>
          )}
        </section>

        <section style={styles.panel}>
          <h2 style={styles.panelTitle}>Reality</h2>
          {recentLogs.length === 0 ? (
            <p style={styles.muted}>Reality logs appear after confirmed check-ins.</p>
          ) : (
            <div style={styles.itemList}>
              {recentLogs.map((log) => (
                <article key={log.id} style={styles.item}>
                  <div style={styles.itemHeader}>
                    <strong>{Math.round(log.completionScore * 100)}%</strong>
                  </div>
                  <p style={styles.itemText}>{log.actualSummary}</p>
                </article>
              ))}
            </div>
          )}
        </section>
      </aside>
    </main>
  );
}

function PlannedBlockSet({ blocks }: { blocks: PlannedBlock[] }) {
  return (
    <div style={styles.artifactList}>
      {blocks.map((block) => (
        <article key={block.id} style={styles.artifact}>
          <div style={styles.itemHeader}>
            <strong>{block.title}</strong>
            <span style={styles.badge}>{block.category}</span>
          </div>
          <p style={styles.muted}>
            {formatTime(block.startTime)} - {formatTime(block.endTime)}
          </p>
          <ul style={styles.criteria}>
            {block.successCriteria.map((criterion) => (
              <li key={criterion}>{criterion}</li>
            ))}
          </ul>
        </article>
      ))}
    </div>
  );
}

function RealityDraftCard({ draft }: { draft: RealityDraft }) {
  return (
    <article style={styles.artifact}>
      <div style={styles.itemHeader}>
        <strong>Reality draft</strong>
        <span style={styles.badge}>{Math.round(draft.completionScore * 100)}%</span>
      </div>
      <p style={styles.itemText}>{draft.actualSummary}</p>
      {draft.deviationReason ? <p style={styles.muted}>{draft.deviationReason}</p> : null}
      {draft.clarificationQuestion ? <p style={styles.itemText}>{draft.clarificationQuestion}</p> : null}
    </article>
  );
}

const styles = {
  shell: {
    minHeight: "100vh",
    display: "grid",
    gridTemplateColumns: "minmax(0, 1fr) 360px",
    gap: 0,
    background: "#f4f1ea",
    color: "#1f2523",
    fontFamily: "Arial, Helvetica, sans-serif"
  },
  chatColumn: {
    minHeight: "100vh",
    display: "grid",
    gridTemplateRows: "auto minmax(0, 1fr) auto auto",
    borderRight: "1px solid #d7d0c2"
  },
  sideColumn: {
    minHeight: "100vh",
    padding: 18,
    display: "grid",
    alignContent: "start",
    gap: 14,
    background: "#fbfaf6"
  },
  topBar: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 16,
    padding: "22px 26px",
    borderBottom: "1px solid #d7d0c2",
    background: "#fbfaf6"
  },
  kicker: {
    margin: 0,
    color: "#67746c",
    fontSize: 13,
    fontWeight: 700,
    textTransform: "uppercase"
  },
  title: {
    margin: "4px 0 0",
    fontSize: 26,
    lineHeight: 1.15,
    letterSpacing: 0
  },
  status: {
    border: "1px solid #b7c6b9",
    borderRadius: 999,
    padding: "7px 11px",
    background: "#e8f0e6",
    color: "#2d5137",
    fontSize: 13,
    fontWeight: 700
  },
  thread: {
    overflow: "auto",
    padding: 26,
    display: "grid",
    alignContent: "start",
    gap: 14
  },
  userBubble: {
    width: "min(720px, 82%)",
    justifySelf: "end",
    borderRadius: 8,
    padding: 14,
    background: "#1f5c57",
    color: "#ffffff"
  },
  assistantBubble: {
    width: "min(760px, 88%)",
    justifySelf: "start",
    border: "1px solid #d7d0c2",
    borderRadius: 8,
    padding: 14,
    background: "#ffffff",
    color: "#1f2523"
  },
  messageRole: {
    marginBottom: 6,
    fontSize: 12,
    fontWeight: 700,
    opacity: 0.75
  },
  messageText: {
    margin: 0,
    lineHeight: 1.5
  },
  suggestions: {
    display: "flex",
    flexWrap: "wrap",
    gap: 8,
    padding: "0 26px 16px"
  },
  suggestionButton: {
    minHeight: 34,
    border: "1px solid #c9c1b2",
    borderRadius: 999,
    padding: "0 12px",
    background: "#fbfaf6",
    color: "#1f2523",
    fontWeight: 700,
    cursor: "pointer"
  },
  composer: {
    display: "grid",
    gridTemplateColumns: "minmax(0, 1fr) auto",
    gap: 10,
    padding: 18,
    borderTop: "1px solid #d7d0c2",
    background: "#fbfaf6"
  },
  composerLabel: {
    display: "grid",
    gap: 7,
    fontSize: 13,
    fontWeight: 700
  },
  composerInput: {
    minHeight: 44,
    border: "1px solid #c9c1b2",
    borderRadius: 8,
    padding: "0 12px",
    background: "#ffffff",
    color: "#1f2523",
    fontSize: 15
  },
  sendButton: {
    alignSelf: "end",
    minHeight: 44,
    border: "1px solid #174d49",
    borderRadius: 8,
    padding: "0 18px",
    background: "#1f5c57",
    color: "#ffffff",
    fontWeight: 700,
    cursor: "pointer"
  },
  panel: {
    border: "1px solid #d7d0c2",
    borderRadius: 8,
    padding: 14,
    background: "#ffffff"
  },
  panelTitle: {
    margin: "0 0 10px",
    fontSize: 17,
    lineHeight: 1.2
  },
  muted: {
    margin: 0,
    color: "#69746f",
    lineHeight: 1.45,
    fontSize: 13
  },
  itemList: {
    display: "grid",
    gap: 10
  },
  item: {
    borderTop: "1px solid #ece6dc",
    paddingTop: 10
  },
  itemHeader: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    gap: 10,
    marginBottom: 6
  },
  itemText: {
    margin: 0,
    lineHeight: 1.45,
    fontSize: 14
  },
  badge: {
    borderRadius: 999,
    padding: "3px 8px",
    background: "#edf0ec",
    color: "#405048",
    fontSize: 12,
    fontWeight: 700,
    whiteSpace: "nowrap"
  },
  artifactList: {
    display: "grid",
    gap: 10,
    marginTop: 12
  },
  artifact: {
    border: "1px solid #d7d0c2",
    borderRadius: 8,
    padding: 12,
    background: "#fbfaf6"
  },
  criteria: {
    margin: "8px 0 0",
    paddingLeft: 18,
    color: "#2b3430",
    lineHeight: 1.5,
    fontSize: 13
  }
} satisfies Record<string, React.CSSProperties>;
