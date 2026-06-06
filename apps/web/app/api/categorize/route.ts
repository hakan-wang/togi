/* ============================================================
   POST /api/categorize  → the categorizer (per togi_categorization_spec.md)
   Body: { text, context:{block,planId,window,kind}, projects:string[], activities:string[], token? }
   Returns: { title, domain, project|null, activity, note|null, confidence, clarify_question|null, via }

   Hard rules enforced in CODE (not trusted to the prompt):
   - domain must be one of the 7 enum values → one retry, else keyword fallback.
   - project/activity fuzzy-matched against the user's existing labels (dedupe).
   - project is only ever a NEW name if the model returned one (prompt only does that
     when the user declared it); otherwise null.
   - JSON validated/normalized before returning.
   Provider: Groq LLM (free) primary; OpenAI fallback; deterministic keyword last resort.
   ============================================================ */
import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const maxDuration = 30;

const DOMAINS = ["Work", "Study", "Health", "Social", "Errands & life admin", "Leisure", "Distraction"] as const;

function systemPrompt(ctx: any, projects: string[], activities: string[]) {
  return [
    "You categorize one time entry for a personal time-clarity app. Input: a cleaned speech-to-text transcript of what the user did (or plans to do), plus the time range, plus the user's existing PROJECTS and ACTIVITIES lists.",
    "",
    "Return ONLY valid JSON matching the schema. No prose.",
    "",
    "Rules:",
    `- domain: choose exactly one of: ${DOMAINS.map((d) => `"${d}"`).join(", ")}. Never invent a domain. Leisure = chosen recreation; Distraction = unintentional time sinks the user regrets (doomscrolling, "fell into TikTok"). Prefer the user's own framing when ambiguous.`,
    "- project: reuse an existing project label whenever one plausibly matches, even if wording differs. Never invent a project yourself: only set a NEW project when the user explicitly declares or names one in the input. Otherwise project: null. Most non-work entries have project: null.",
    "- activity: pick from the existing ACTIVITIES list whenever possible; consistency beats precision. If nothing fits, create a new 1-3 word verb-first term reusable across projects.",
    "- note: a cleaned one-line summary in the user's own language, max 12 words, ONLY if it adds information beyond domain+project+activity. Otherwise null. Never copy rambling transcript text.",
    "- title: a short human-readable calendar block title, 2-5 words (e.g. \"Email co-manufacturers\", \"Fell into TikTok\"). English.",
    "- confidence: 0-1. If below 0.6, also fill clarify_question with ONE short question Togi can ask the user.",
    "",
    `EXISTING PROJECTS: ${projects.length ? projects.join(", ") : "(none yet)"}`,
    `EXISTING ACTIVITIES: ${activities.length ? activities.join(", ") : "(none yet)"}`,
    ctx?.block
      ? `CONTEXT: the block that just ended is "${ctx.block}"${ctx.window ? ` (${ctx.window})` : ""}. If the user describes doing that, matched=true; if they did something else, matched=false.`
      : "CONTEXT: no specific planned block (self check-in).",
    "",
    'JSON schema: {"title":string,"domain":one-of-the-7,"project":string|null,"activity":string,"note":string|null,"confidence":number,"clarify_question":string|null,"matched":boolean}',
  ].join("\n");
}

function normDomain(d: any): string | null {
  if (!d) return null;
  const t = String(d).trim().toLowerCase();
  for (const dom of DOMAINS) if (dom.toLowerCase() === t) return dom;
  if (t.startsWith("errand") || t.includes("life admin")) return "Errands & life admin";
  return null;
}

// fuzzy-snap a label to an existing one (exact, then substring); else keep as-is (new)
function snap(name: any, list: string[]): string | null {
  if (name == null || name === "") return null;
  const n = String(name).trim();
  const nl = n.toLowerCase();
  for (const x of list) if (x.trim().toLowerCase() === nl) return x;
  for (const x of list) { const xl = x.trim().toLowerCase(); if (xl && (xl.includes(nl) || nl.includes(xl))) return x; }
  return n;
}

function parseDuration(text: string): number | null {
  const h = text.match(/(\d+(?:\.\d+)?)\s*(?:h|hour|hr|timm)/i);
  const m = text.match(/(\d+)\s*(?:m|min)/i);
  let mins = 0;
  if (h) mins += Math.round(parseFloat(h[1]) * 60);
  if (m) mins += parseInt(m[1], 10);
  return mins || null;
}

const KW: Array<[RegExp, { domain: string; activity: string }]> = [
  [/scroll|tiktok|instagram|insta|reels|doomscroll|fell into/i, { domain: "Distraction", activity: "Scrolling" }],
  [/gym|workout|run|lift|strength|exercise|padel|walk/i, { domain: "Health", activity: "Gym" }],
  [/edit|vlog|film|footage|cut /i, { domain: "Work", activity: "Editing" }],
  [/email|mail|supplier|manufactur|inbox/i, { domain: "Work", activity: "Email" }],
  [/wrote|writing|doc|formula|thesis|essay/i, { domain: "Work", activity: "Writing" }],
  [/stud|exam|homework|revis|course/i, { domain: "Study", activity: "Studying" }],
  [/read/i, { domain: "Leisure", activity: "Reading" }],
  [/friend|cinema|movie|hang|dinner|party|family|call/i, { domain: "Social", activity: "Hanging out" }],
  [/shop|errand|post office|return|grocery|commut|clean|laundry|dishes/i, { domain: "Errands & life admin", activity: "Errands" }],
  [/eat|lunch|meal|cook|nap|rest|relax|game|gaming|watch|netflix/i, { domain: "Leisure", activity: "Resting" }],
];
function keywordResult(text: string) {
  let hit = { domain: "Work", activity: "Deep work" };
  for (const [re, v] of KW) if (re.test(text)) { hit = v; break; }
  const words = text.replace(/\s+/g, " ").trim().split(" ").slice(0, 4).join(" ");
  return { title: words.charAt(0).toUpperCase() + words.slice(1), domain: hit.domain, project: null, activity: hit.activity, note: null, confidence: 0.7, clarify_question: null, matched: false };
}

async function callLLM(baseURL: string | undefined, key: string, model: string, sys: string, user: string) {
  const OpenAI = (await import("openai")).default;
  const client = new OpenAI({ apiKey: key, baseURL });
  const r = await client.chat.completions.create({
    model, temperature: 0,
    messages: [{ role: "system", content: sys }, { role: "user", content: user }],
    response_format: { type: "json_object" },
  });
  return JSON.parse(r.choices[0]?.message?.content || "{}");
}

function finalize(obj: any, text: string, projects: string[], activities: string[], via: string) {
  const domain = normDomain(obj.domain);
  if (!domain) return null; // signal caller to retry
  return {
    title: (obj.title && String(obj.title).slice(0, 60)) || text.split(/\s+/).slice(0, 4).join(" "),
    domain,
    project: snap(obj.project, projects),                 // null stays null; existing snaps; new kept
    activity: snap(obj.activity, activities) || "Deep work",
    note: obj.note ? String(obj.note).slice(0, 90) : null,
    confidence: typeof obj.confidence === "number" ? obj.confidence : 0.75,
    clarify_question: obj.clarify_question || null,
    matched: !!obj.matched,
    durationMin: obj.durationMin ?? parseDuration(text),
    via,
  };
}

export async function POST(req: NextRequest) {
  const { text, context = {}, projects = [], activities = [] } = await req.json();
  if (!text || !text.trim()) return NextResponse.json({ error: "no_text" }, { status: 400 });

  const sys = systemPrompt(context, projects, activities);
  const userMsg = `Time entry transcript: "${text}"${context.window ? `\nTime range: ${context.window}` : ""}`;

  // Provider chain: Groq → OpenAI. Each gets ONE retry if the domain is invalid.
  const providers: Array<{ via: string; baseURL?: string; key?: string; model: string }> = [];
  if (process.env.GROQ_API_KEY) providers.push({ via: "groq", baseURL: "https://api.groq.com/openai/v1", key: process.env.GROQ_API_KEY, model: "llama-3.3-70b-versatile" });
  if (process.env.OPENAI_API_KEY) providers.push({ via: "openai", key: process.env.OPENAI_API_KEY, model: "gpt-4o-mini" });

  for (const p of providers) {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const sysMsg = attempt === 0 ? sys : sys + `\n\nIMPORTANT: domain MUST be exactly one of ${DOMAINS.join(" | ")}.`;
        const obj = await callLLM(p.baseURL, p.key!, p.model, sysMsg, userMsg);
        const out = finalize(obj, text, projects, activities, p.via);
        if (out) return NextResponse.json(out);
      } catch (e) {
        console.warn(`categorize ${p.via} attempt ${attempt} error:`, e);
        break; // network/parse error → next provider
      }
    }
  }

  // Last resort: deterministic keyword classifier (always valid schema)
  return NextResponse.json(finalize(keywordResult(text), text, projects, activities, "keyword"));
}
