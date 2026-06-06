"use client";

import { useEffect, useRef, useState } from "react";
import type { PlannedBlock } from "@/server/schemas/planned-blocks";
import type { Goal } from "@/server/schemas/goals";
import type { RealityLog } from "@/server/schemas/reality-logs";
import type { ChatResponse, RealityDraft, ToolCall } from "@/server/services/chat/schemas";

type AssistantTurn = {
  role: "assistant";
  text: string;
  activity: string[];
  plannedBlocks: PlannedBlock[];
  realityDraft: RealityDraft | null;
};

type UserTurn = { role: "user"; text: string };
type Turn = UserTurn | AssistantTurn;

const SUGGESTIONS = [
  "Plan a 90-minute deep work block tomorrow morning to draft my talk",
  "Check in on my draft block — I wrote the outline but didn't finish",
  "How am I doing against my goals this week?"
];

// User-facing labels for what the coach did, never raw tool traces.
const ACTIVITY_LABELS: Record<string, string> = {
  list_goals: "Reviewed your goals",
  list_planned_blocks: "Checked your schedule",
  create_planned_block: "Created a plan block",
  draft_reality_log: "Drafted a check-in",
  list_reality_logs: "Reviewed your history",
  coach_from_history: "Looked at your patterns"
};

const describeActivity = (calls: ToolCall[]): string[] => {
  const seen = new Set<string>();
  const labels: string[] = [];
  for (const call of calls) {
    const base = ACTIVITY_LABELS[call.name] ?? "Worked on it";
    const label = call.status === "failed" ? `${base} (couldn't finish)` : base;
    if (!seen.has(label)) {
      seen.add(label);
      labels.push(label);
    }
  }
  return labels;
};

const formatWhen = (startTime: string, endTime: string): string => {
  try {
    const start = new Date(startTime);
    const end = new Date(endTime);
    const day = start.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
    const t = (d: Date) => d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
    return `${day} · ${t(start)} – ${t(end)}`;
  } catch {
    return `${startTime} – ${endTime}`;
  }
};

export default function Home() {
  const [userId, setUserId] = useState<string | null>(null);
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [goals, setGoals] = useState<Goal[]>([]);
  const [plannedBlocks, setPlannedBlocks] = useState<PlannedBlock[]>([]);
  const [realityLogs, setRealityLogs] = useState<RealityLog[]>([]);
  const [confirmedDrafts, setConfirmedDrafts] = useState<Record<string, boolean>>({});

  const threadRef = useRef<HTMLDivElement>(null);

  // Establish a stable anonymous identity for this browser. Never shown to the user.
  useEffect(() => {
    const key = "togi.user";
    let id = window.localStorage.getItem(key);
    if (!id) {
      id = window.crypto?.randomUUID?.() ?? `u-${Date.now()}`;
      window.localStorage.setItem(key, id);
    }
    setUserId(id);
  }, []);

  useEffect(() => {
    threadRef.current?.scrollTo({ top: threadRef.current.scrollHeight, behavior: "smooth" });
  }, [turns, sending]);

  const send = async (message: string) => {
    const text = message.trim();
    if (!text || sending || !userId) return;

    setInput("");
    setError(null);
    setTurns((prev) => [...prev, { role: "user", text }]);
    setSending(true);

    try {
      const response = await fetch("/api/chat", {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${userId}` },
        body: JSON.stringify({ message: text })
      });

      if (!response.ok) {
        throw new Error("The coach hit a snag. Try again in a moment.");
      }

      const data = (await response.json()) as ChatResponse;
      setTurns((prev) => [
        ...prev,
        {
          role: "assistant",
          text: data.assistantMessage,
          activity: describeActivity(data.toolCalls),
          plannedBlocks: data.artifacts.plannedBlocks,
          realityDraft: data.artifacts.realityDraft
        }
      ]);
      setGoals(data.state.goals);
      setPlannedBlocks(data.state.plannedBlocks);
      setRealityLogs(data.state.realityLogs);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Something went wrong.");
    } finally {
      setSending(false);
    }
  };

  const confirmDraft = async (draft: RealityDraft) => {
    if (!userId) return;
    try {
      const response = await fetch("/api/reality-logs", {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${userId}` },
        body: JSON.stringify({
          plannedBlockId: draft.plannedBlockId,
          actualSummary: draft.actualSummary,
          completionScore: draft.completionScore,
          deviationReason: draft.deviationReason,
          actualCategories: draft.actualCategories,
          confirmedByUser: true
        })
      });
      if (!response.ok) throw new Error("Could not save that check-in.");
      const saved = (await response.json()) as RealityLog;
      setRealityLogs((prev) => [...prev, saved]);
      setConfirmedDrafts((prev) => ({ ...prev, [draft.plannedBlockId]: true }));
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Could not save that check-in.");
    }
  };

  const onSubmit = (event: React.FormEvent) => {
    event.preventDefault();
    void send(input);
  };

  const onKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      void send(input);
    }
  };

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <span className="dot" />
          <h1>Togi</h1>
        </div>
        <p className="tagline">Plan with intention. Reflect on reality.</p>

        <div className="section-title">Goals</div>
        <div className="pill-list">
          {goals.length === 0 ? (
            <p className="empty">No goals yet — tell Togi what matters.</p>
          ) : (
            goals.map((goal) => (
              <div key={goal.id} className="state-card">
                <div className="title">{goal.title}</div>
                <div className="meta">{goal.status}</div>
              </div>
            ))
          )}
        </div>

        <div className="section-title">Today&apos;s plan</div>
        <div className="pill-list">
          {plannedBlocks.length === 0 ? (
            <p className="empty">Nothing scheduled. Ask Togi to plan a block.</p>
          ) : (
            plannedBlocks.map((block) => (
              <div key={block.id} className="state-card">
                <div className="title">{block.title}</div>
                <div className="meta">{formatWhen(block.startTime, block.endTime)}</div>
              </div>
            ))
          )}
        </div>

        <div className="section-title">Reality logs</div>
        <div className="pill-list">
          {realityLogs.length === 0 ? (
            <p className="empty">No reflections yet.</p>
          ) : (
            realityLogs.map((log) => (
              <div key={log.id} className="state-card">
                <div className="title">{log.actualSummary}</div>
                <div className="meta">{Math.round(log.completionScore * 100)}% to plan</div>
              </div>
            ))
          )}
        </div>
      </aside>

      <main className="main">
        <div className="thread" ref={threadRef}>
          {turns.length === 0 ? (
            <div className="hero">
              <h2>What are you taking on?</h2>
              <p>Togi turns vague intentions into checkable plans, then helps you reflect honestly on what really happened.</p>
              <div className="suggestions">
                {SUGGESTIONS.map((prompt) => (
                  <button key={prompt} type="button" className="suggestion" onClick={() => void send(prompt)}>
                    {prompt}
                  </button>
                ))}
              </div>
            </div>
          ) : (
            turns.map((turn, index) =>
              turn.role === "user" ? (
                <div key={index} className="msg-row user">
                  <div className="bubble user">{turn.text}</div>
                </div>
              ) : (
                <div key={index}>
                  <div className="msg-row">
                    <div className="bubble assistant">
                      {turn.activity.length > 0 && (
                        <div className="activity">
                          {turn.activity.map((label) => (
                            <span key={label} className={`chip${label.includes("couldn't") ? " failed" : ""}`}>
                              {label}
                            </span>
                          ))}
                        </div>
                      )}
                      {turn.text}
                    </div>
                  </div>

                  {(turn.plannedBlocks.length > 0 || turn.realityDraft) && (
                    <div className="cards">
                      {turn.plannedBlocks.map((block) => (
                        <div key={block.id} className="card">
                          <div className="kicker">Plan block</div>
                          <h3>{block.title}</h3>
                          <div className="when">{formatWhen(block.startTime, block.endTime)}</div>
                          <div className="intention">{block.intentionText}</div>
                          <ul className="criteria">
                            {block.successCriteria.map((criterion, i) => (
                              <li key={i}>{criterion}</li>
                            ))}
                          </ul>
                        </div>
                      ))}

                      {turn.realityDraft && (
                        <div className="card draft">
                          <div className="kicker">Check-in draft</div>
                          <div className="intention">{turn.realityDraft.actualSummary}</div>
                          <div className="score">
                            Hit <b>{Math.round(turn.realityDraft.completionScore * 100)}%</b> of your plan
                          </div>
                          {turn.realityDraft.deviationReason && (
                            <div className="when">{turn.realityDraft.deviationReason}</div>
                          )}
                          {turn.realityDraft.clarificationQuestion && (
                            <div className="intention">{turn.realityDraft.clarificationQuestion}</div>
                          )}
                          <p className="draft-note">This is a draft — nothing is saved until you confirm it.</p>
                          {confirmedDrafts[turn.realityDraft.plannedBlockId] ? (
                            <span className="confirmed-tag">✓ Saved to your reality logs</span>
                          ) : (
                            <button type="button" className="btn" onClick={() => turn.realityDraft && void confirmDraft(turn.realityDraft)}>
                              Yes, that&apos;s what happened
                            </button>
                          )}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )
            )
          )}

          {sending && <div className="typing">Togi is thinking…</div>}
          {error && <div className="typing">{error}</div>}
        </div>

        <div className="composer">
          <form onSubmit={onSubmit}>
            <textarea
              value={input}
              onChange={(event) => setInput(event.target.value)}
              onKeyDown={onKeyDown}
              rows={1}
              placeholder="Tell Togi what you're planning, or how a block actually went…"
            />
            <button type="submit" className="btn" disabled={sending || input.trim().length === 0}>
              Send
            </button>
          </form>
        </div>
      </main>
    </div>
  );
}
