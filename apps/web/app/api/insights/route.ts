/* ============================================================
   POST /api/insights — { stats, memory } → { insights: [...] }
   The AI pass from togi_insights_spec.md §8: turn pre-computed STATS into human
   insights that pass the Miss Test, reconciled against EXISTING memory. Groq LLM.
   Hard rules (evidence floor, dedupe, cap, language) are enforced in code
   (stats engine + insightMemory.ts), not here.
   ============================================================ */
import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const maxDuration = 30;

const FAMILIES = ["drift", "estimation", "distraction", "rhythm", "follow_through", "second_order"];

const SYSTEM = [
  "You maintain a behavioral-insight memory for a personal time-clarity app. You receive pre-computed STATS about the user's last ~2-3 weeks (plan vs real) and the user's EXISTING insight memory.",
  "Your job: surface ONLY insights the user would NOT notice on their own.",
  "",
  "THE MISS TEST — an insight qualifies ONLY if the user couldn't see it from inside a single day. Reject anything that just restates one check-in (e.g. 'you scrolled 2h today' — they logged it, they know). Favor patterns that are: emergent across days, relational (plan vs real, activity→distraction, time→follow-through), quantified, counter to the user's assumptions, and actionable.",
  "",
  `For each qualifying pattern return: family (one of: ${FAMILIES.join(", ")}), a short human STATEMENT with a number/frequency in it, a METRIC tag (e.g. "+90 min/day", "5 of 7 days", "before 11am"), an optional SUGGESTION (one concrete planning change), CONFIDENCE 0-1, the evidence_count it's based on, and RECONCILE: "new" or "confirms:<id>" or "contradicts:<id>" vs the existing memory.`,
  "",
  "Rules: never restate a single event; never moralize or guilt; be warm and neutral; be specific and quantified (no vague 'be productive'); prefer fewer high-value insights; if a stat is thin, mark confidence low.",
  'Return ONLY valid JSON: { "insights": [ {family, statement, metric, suggestion, confidence, evidence_count, reconcile} ] }',
].join("\n");

export async function POST(req: NextRequest) {
  const { stats, memory = [] } = await req.json();
  if (!stats) return NextResponse.json({ error: "no_stats" }, { status: 400 });

  const key = process.env.GROQ_API_KEY || process.env.OPENAI_API_KEY;
  if (!key) return NextResponse.json({ insights: [] });
  const baseURL = process.env.GROQ_API_KEY ? "https://api.groq.com/openai/v1" : undefined;
  const model = process.env.GROQ_API_KEY ? "llama-3.3-70b-versatile" : "gpt-4o-mini";

  const userMsg = [
    `STATS (last ${stats.days} days):`,
    JSON.stringify(stats, null, 1),
    "",
    "EXISTING MEMORY:",
    memory.length ? memory.map((m: any) => `- [${m.id}] (${m.status}) ${m.statement}`).join("\n") : "(empty)",
  ].join("\n");

  try {
    const OpenAI = (await import("openai")).default;
    const client = new OpenAI({ apiKey: key, baseURL });
    const r = await client.chat.completions.create({
      model, temperature: 0.2,
      messages: [{ role: "system", content: SYSTEM }, { role: "user", content: userMsg }],
      response_format: { type: "json_object" },
    });
    const obj = JSON.parse(r.choices[0]?.message?.content || "{}");
    const insights = Array.isArray(obj.insights) ? obj.insights.filter((i: any) => i && i.statement && FAMILIES.includes(i.family)) : [];
    return NextResponse.json({ insights });
  } catch (e: any) {
    console.warn("insights LLM error:", e);
    return NextResponse.json({ insights: [], error: String(e?.message || e) });
  }
}
