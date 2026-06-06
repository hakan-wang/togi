/* ============================================================
   POST /api/categorize  — { text, context, token } → CategorizeResult
   Primary brain: the existing deployed Togi backend (/v1/infer, Claude via Bedrock,
   tool/structured output). The Supabase access token (when signed in) is forwarded
   so the backend authorizes the call.

   Resilience (so the vertical slice is never dead): if the backend is unreachable or
   rejects the call (e.g. no token / quota), we fall back to OpenAI structured output
   if a key exists, and finally to a deterministic keyword classifier. The path is
   reported back in `via` for debugging.
   ============================================================ */
import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const maxDuration = 30;

const CATEGORY_KEYS = ["deepwork", "creative", "admin", "health", "social", "errands", "leisure", "scroll", "personal"];

const TOOL = {
  name: "log_entry",
  description: "Record one categorized Real time-entry from the user's spoken/typed check-in.",
  input_schema: {
    type: "object",
    properties: {
      category: { type: "string", enum: CATEGORY_KEYS, description: "Broad bucket." },
      subCategory: { type: "string", description: "Specific recurring activity, e.g. Litro, TikTok, Gym, Editing, Suppliers. Reuse existing labels when they fit." },
      description: { type: "string", description: "Short detail of what actually happened (max ~8 words)." },
      durationMin: { type: ["integer", "null"], description: "Minutes spent if stated or clearly implied, else null." },
      matchedPlanId: { type: ["string", "null"], description: "The provided planId if this activity matches the planned block, else null." },
      matched: { type: "boolean", description: "True if reality matched the planned intention." },
    },
    required: ["category", "subCategory", "description", "matched"],
  },
};

function systemPrompt(ctx: any) {
  return [
    "You are Togi, an accountability coach. Categorize one check-in into exactly three levels:",
    "Category > Sub-category > Description. Call the log_entry tool once. Do not write prose.",
    `Allowed categories: ${CATEGORY_KEYS.join(", ")}.`,
    "Reuse consistent sub-category labels over time (Litro, TikTok, Gym, Editing, Suppliers, Town, Friends, Meals, Tidying).",
    "Map social media / doom-scrolling to category 'scroll'. Map focused project work to 'deepwork' or 'creative'.",
    ctx?.block ? `The block that just ended: "${ctx.block}"${ctx.planId ? ` (planId ${ctx.planId})` : ""}${ctx.window ? `, scheduled ${ctx.window}` : ""}. If the user describes doing that, set matchedPlanId to its planId and matched=true; if they did something else, matched=false and matchedPlanId=null.` : "No specific planned block; treat as self check-in (matched=false, matchedPlanId=null).",
  ].join("\n");
}

const FALLBACK_KEYWORDS: Array<[RegExp, { category: string; subCategory: string }]> = [
  [/scroll|tiktok|instagram|insta|reels|twitter|youtube|phone/i, { category: "scroll", subCategory: "TikTok" }],
  [/gym|workout|run|lift|strength|exercise/i, { category: "health", subCategory: "Gym" }],
  [/edit|vlog|video|footage|cut /i, { category: "creative", subCategory: "Editing" }],
  [/email|reply|inbox|supplier|manufactur/i, { category: "admin", subCategory: "Suppliers" }],
  [/litro|formula|doc|write|wrote|thesis|read/i, { category: "deepwork", subCategory: "Litro" }],
  [/friend|cinema|movie|hang|dinner|party/i, { category: "social", subCategory: "Friends" }],
  [/shop|errand|post office|return|grocery|town/i, { category: "errands", subCategory: "Town" }],
  [/clean|tidy|laundry|dishes|desk/i, { category: "personal", subCategory: "Tidying" }],
  [/eat|lunch|meal|cook|nap|rest|relax/i, { category: "leisure", subCategory: "Break" }],
];

function parseDuration(text: string): number | null {
  const h = text.match(/(\d+(?:\.\d+)?)\s*(?:h|hour|hr)/i);
  const m = text.match(/(\d+)\s*(?:m|min)/i);
  let mins = 0;
  if (h) mins += Math.round(parseFloat(h[1]) * 60);
  if (m) mins += parseInt(m[1], 10);
  return mins || null;
}

function shortPhrase(text: string, max = 42): string {
  const clean = text.replace(/\s+/g, " ").trim();
  if (clean.length <= max) return clean;
  const cut = clean.slice(0, max);
  const lastSpace = cut.lastIndexOf(" ");
  return (lastSpace > 12 ? cut.slice(0, lastSpace) : cut) + "…";
}

function keywordFallback(text: string, ctx: any) {
  let cat = { category: "personal", subCategory: "General" };
  for (const [re, c] of FALLBACK_KEYWORDS) if (re.test(text)) { cat = c; break; }
  const matched = !!ctx?.planId && new RegExp((ctx.block || "").split(/\s+/).slice(0, 2).join("|"), "i").test(text);
  return {
    category: cat.category,
    subCategory: cat.subCategory,
    description: shortPhrase(text),
    durationMin: parseDuration(text),
    matchedPlanId: matched ? ctx.planId : null,
    matched,
  };
}

export async function POST(req: NextRequest) {
  const { text, context = {}, token } = await req.json();
  if (!text || !text.trim()) return NextResponse.json({ error: "no_text" }, { status: 400 });

  const messages = [{ role: "user", content: `Check-in: "${text}"` }];

  // 1) Primary: the deployed Togi backend (Claude + tools)
  const base = process.env.BACKEND_BASE_URL;
  if (base) {
    try {
      const res = await fetch(`${base}/v1/infer`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { "X-Bogi-Authorization": `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({ system: systemPrompt(context), messages, tools: [TOOL], maxTokens: 400, temperature: 0 }),
      });
      if (res.ok) {
        const data = await res.json();
        const tool = (data.content || []).find((c: any) => c.type === "tool_use");
        if (tool?.input) {
          return NextResponse.json(normalize(tool.input, text, context, "backend"));
        }
      } else {
        console.warn("backend categorize non-200:", res.status);
      }
    } catch (e) {
      console.warn("backend categorize error:", e);
    }
  }

  // 2) Groq LLM structured output (free; reuses the transcription key). Real LLM
  //    categorization without needing backend auth — great default for the demo.
  if (process.env.GROQ_API_KEY) {
    try {
      const OpenAI = (await import("openai")).default;
      const groq = new OpenAI({ apiKey: process.env.GROQ_API_KEY, baseURL: "https://api.groq.com/openai/v1" });
      const r = await groq.chat.completions.create({
        model: "llama-3.3-70b-versatile",
        temperature: 0,
        messages: [
          { role: "system", content: systemPrompt(context) + "\nRespond ONLY with a JSON object: {category, subCategory, description, durationMin, matchedPlanId, matched}." },
          { role: "user", content: `Check-in: "${text}"` },
        ],
        response_format: { type: "json_object" },
      });
      const obj = JSON.parse(r.choices[0]?.message?.content || "{}");
      return NextResponse.json(normalize(obj, text, context, "groq"));
    } catch (e) {
      console.warn("groq categorize error:", e);
    }
  }

  // 3) Fallback: OpenAI structured output (if a key is present)
  if (process.env.OPENAI_API_KEY) {
    try {
      const OpenAI = (await import("openai")).default;
      const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
      const r = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        temperature: 0,
        messages: [
          { role: "system", content: systemPrompt(context) + "\nRespond ONLY with JSON: {category, subCategory, description, durationMin, matchedPlanId, matched}." },
          { role: "user", content: `Check-in: "${text}"` },
        ],
        response_format: { type: "json_object" },
      });
      const obj = JSON.parse(r.choices[0]?.message?.content || "{}");
      return NextResponse.json(normalize(obj, text, context, "openai"));
    } catch (e) {
      console.warn("openai categorize error:", e);
    }
  }

  // 3) Last resort: deterministic keyword classifier (always works, no network)
  return NextResponse.json({ ...normalize(keywordFallback(text, context), text, context, "keyword") });
}

function normalize(o: any, text: string, ctx: any, via: string) {
  const category = CATEGORY_KEYS.includes(o.category) ? o.category : "personal";
  return {
    category,
    subCategory: o.subCategory || "General",
    description: o.description || text.slice(0, 60),
    durationMin: o.durationMin ?? parseDuration(text),
    matchedPlanId: o.matchedPlanId ?? null,
    matched: !!o.matched,
    via,
  };
}
