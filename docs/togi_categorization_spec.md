# Togi — Categorization Spec (v1)

How every check-in and every planned block gets categorized. This spec is the contract between the voice pipeline (speech-to-text via Groq), the categorizer LLM call, and Supabase. Guidelines live in the categorizer's system prompt (included below); hard rules are enforced in code, never trusted to the prompt alone.

## Why not a 3-level tree

"Work" and "Working on Litro" are not parent and child, they are different kinds of information. A single Category > Sub-category > Description tree forces wrong choices and inconsistent data. Instead, every time entry gets four independent fields.

## The four fields

| Field | What it is | Who controls the list | Example |
|---|---|---|---|
| domain | The fixed top-level bucket. Drives colors and top-level analytics. | System. Fixed list of 7. The AI must pick exactly one and may NEVER invent a new one. | Work |
| project | A recurring, named endeavor spanning many sessions. Optional (null when none fits; never force one). | User's list grows over time. The AI must reuse an existing label when one plausibly matches; creating a new project should be rare. | Litro |
| activity | What was actually done, as a short reusable verb phrase. This powers cross-cutting insights ("you scroll when you planned editing"), so consistency matters more than precision. | Controlled vocabulary (starter list below). The AI reuses existing terms; it may propose a new one only when nothing fits. | Email suppliers |
| note | A cleaned-up one-liner from the voice input. OPTIONAL: include only if it adds information beyond domain+project+activity. Max ~12 words. Never the raw rambling transcript. | Free text. | Contract terms to two co-manufacturers |

Display naming in the UI: call them Domain (or just the color), Project, Activity, Note. Never show "Category / Sub-category" labels to the user; a block renders as Activity as the title, Project as a chip, Note as a subtitle when present.

## The 7 domains (fixed)

1. **Work** — paid/professional/entrepreneurial work.
2. **Study** — school, courses, homework, exam prep.
3. **Health** — gym, sports, walks, sleep routines, doctor.
4. **Social** — time with friends, family, partner; calls included.
5. **Errands & life admin** — chores, shopping, commuting/travel time, paperwork.
6. **Leisure** — intentional recreation: gaming on purpose, movies, hobbies, reading.
7. **Distraction** — unintentional time sinks: doomscrolling, "fell into TikTok", aimless browsing. Separate from Leisure on purpose: chosen rest is not the same as leaked time, and this domain powers Togi's most valuable insights.

Rule of thumb the AI applies: if the user chose it and would do it again, Leisure. If it happened to them and they regret the time, Distraction. When genuinely ambiguous, prefer the user's own framing in the voice note.

## Consistency rules (enforced in code)

1. domain must be one of the 7 enum values. Reject and retry the LLM call otherwise.
2. Before each categorizer call, fetch the user's existing project labels and activity vocabulary from Supabase and inject them into the prompt. The categorizer must map to existing labels when plausible (fuzzy/semantic match: "litro mail", "emailed Litro suppliers" → project: Litro, activity: Email suppliers).
3. New projects come from the USER, not the AI: a project is created only when the user explicitly names one ("this is a new project", or clearly introduces a named endeavor like "started working on Boogie"). The AI never infers or invents project names on its own; if nothing matches the existing list and the user did not declare one, project = null.
4. New activity creation is allowed and expected: the AI creates a new activity whenever nothing in the existing vocabulary fits; keep it 1–3 words, verb-first, reusable across projects. Activities must be USER-EDITABLE after the fact (rename, merge, re-assign) — store them as rows the user can manage, not hardcoded strings.
5. note is dropped entirely when it would just restate the activity.
6. Same pipeline categorizes BOTH planned blocks (during planning sessions) and real entries (during check-ins), writing to the same vocabulary, so Plan and Real stay comparable.

## Starter activity vocabulary

Editing, Filming, Writing, Email, Meeting, Planning, Deep work, Admin, Studying, Reading, Gym, Walk, Cooking, Eating, Commuting, Errands, Cleaning, Hanging out, Call, Gaming, Watching, Scrolling, Resting.

(Seed Supabase with these; the list grows per user under rule 4.)

## Categorizer system prompt (paste into the LLM call)

```
You categorize one time entry for a personal time-clarity app. Input: a cleaned speech-to-text transcript of what the user did (or plans to do), plus the time range, plus the user's existing PROJECTS and ACTIVITIES lists.

Return ONLY valid JSON matching the schema. No prose.

Rules:
- domain: choose exactly one of: Work, Study, Health, Social, "Errands & life admin", Leisure, Distraction. Never invent a domain. Leisure = chosen recreation; Distraction = unintentional time sinks the user regrets (doomscrolling, "fell into TikTok"). Prefer the user's own framing when ambiguous.
- project: reuse an existing project label whenever one plausibly matches the input, even if the wording differs. Never invent a project yourself: only set a NEW project when the user explicitly declares or names one in the input. Otherwise, if nothing matches, project: null. Most non-work entries have project: null.
- activity: pick from the existing ACTIVITIES list whenever possible; consistency beats precision. If nothing fits, create a new 1-3 word verb-first term that would be reusable across projects — this is allowed and expected.
- note: a cleaned one-line summary in the user's language, max 12 words, ONLY if it adds information beyond domain+project+activity. Otherwise null. Never copy rambling transcript text.
- title: a short human-readable block title for the calendar, 2-5 words, based on the activity and input (e.g. "Email co-manufacturers", "Fell into TikTok").
- confidence: 0-1. If below 0.6, also fill clarify_question with ONE short question Togi can ask the user.

JSON schema:
{
  "title": string,
  "domain": "Work" | "Study" | "Health" | "Social" | "Errands & life admin" | "Leisure" | "Distraction",
  "project": string | null,
  "activity": string,
  "note": string | null,
  "confidence": number,
  "clarify_question": string | null
}
```

## Worked examples

Voice: "jag mailade två kontraktstillverkare om villkoren för Litro"
→ { title: "Email co-manufacturers", domain: "Work", project: "Litro", activity: "Email", note: "Contract terms to two co-manufacturers", confidence: 0.95, clarify_question: null }

Voice: "ärligt talat fastnade jag på TikTok i typ en timme"
→ { title: "Fell into TikTok", domain: "Distraction", project: null, activity: "Scrolling", note: null, confidence: 0.97, clarify_question: null }

Voice: "käkade lunch och diskade"
→ { title: "Lunch + dishes", domain: "Errands & life admin", project: null, activity: "Eating", note: "Lunch and dishes", confidence: 0.8, clarify_question: null }

Voice: "var med Elias och spelade padel"
→ { title: "Padel with Elias", domain: "Social", project: null, activity: "Hanging out", note: "Padel with Elias", confidence: 0.9, clarify_question: null }
(Health would also be defensible; Social wins because the user framed it around the friend. This is exactly the kind of call the confidence field exists for.)

## Analytics implication

Because domain is a fixed enum and activity is a controlled vocabulary, every analytics query in Insights becomes trivial and reliable: filter by domain (the old "invisible fourth category" problem is solved, it is just the first field), group by project within Work, find patterns by activity across all domains ("when do I scroll most"). No string-soup deduplication needed later.
