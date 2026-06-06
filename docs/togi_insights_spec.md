# Togi — Insights Spec (v1): "What counts as an insight you'd miss"

How Togi turns a pile of check-ins into a small, living **memory of how the user behaves**. This is the behavioral-data moat. It is the contract between the data (Supabase `real_entries` + `plan`), the insight-extraction LLM call, and the insight memory store.

Companion to `togi_categorization_spec.md`. Guidelines live in the system prompt (below); **hard rules are enforced in code, never trusted to the prompt alone.** This document is meant to be **added to over time** — new insight families and rules go here first, then into code.

---

## 1. Why this exists

Togi already gives the user clarity in the moment: they check in, they see they scrolled. That's table stakes. The *moat* is the stuff a person **cannot see from inside their own day** — patterns that only emerge across days and across the gap between plan and reality. The job of Insights is to find exactly those, store them as memory, and (later) use them to plan better.

The product loop: **track → notice the non-obvious → remember it → plan around it.** This spec covers *notice* and *remember*.

---

## 2. The one test that decides everything: the **Miss Test**

> An observation is an **Insight** only if the user would **not** notice it on their own.

If the user already knows it because they just lived it or just logged it, it is **noise**, not an insight. Surfacing noise makes Togi feel dumb and erodes trust.

A miss-worthy insight has most of these properties:

| Property | Meaning | Example |
|---|---|---|
| **Emergent, not momentary** | Invisible in any single check-in; only visible summed across time. | 90 min/day lost to travel — nothing per trip, glaring over a week. |
| **Relational / cross-referenced** | Links two things the user holds separately (plan vs real, activity→distraction, time-of-day→follow-through). | "TikTok opens *during* editing blocks." |
| **Quantified past gut-feel** | Turns a vague feeling into a number/frequency. | "Days feel short" → "you lose 1h40 inside planned focus blocks, 4 days running." |
| **Counter to self-story** | Reveals the gap between what the user thinks they do and what they do. | "Deep work after lunch never actually happens." |
| **Actionable** | Implies a concrete better plan. If it can't change a decision, it's trivia. | "Schedule editing after 3pm, where it actually happens." |

**Rule of thumb:** a single logged event the user just reported can **never** be an insight. It only becomes one when it **recurs or accumulates** into a pattern.

---

## 3. What does NOT count (noise — never surface)

- **Restating one check-in** the user just made ("you scrolled 2h today"). They know.
- **One-off events** with no recurrence and no accumulation.
- **Things the user named/framed themselves** in their own words.
- **Expected totals** (slept ~8h, worked ~8h on a workday) — unless they *deviate from the user's own baseline*.
- **Judgment or moralizing** ("you waste too much time"). Togi describes; it never scolds.
- **Under-evidenced guesses** — below the evidence threshold (see §6). Keep as a hidden *candidate*, don't show it.

---

## 4. Insight families (the kinds that pass the test)

Extensible list. Every surfaced insight is tagged with exactly one family.

1. **Plan→Reality drift** — recurring slips and substitutions: "planned X, did Y, N times," including *displacement* ("the edit didn't fail, it moved to 15:10 — it usually does").
2. **Systematic estimation error** — activities/domains that consistently run longer or shorter than planned; the hidden, cumulative cost (the 90-min/day errands gap). Invisible per-instance, large in aggregate.
3. **Distraction triggers & couplings** — what context *precedes* leaked time ("scrolling starts inside editing blocks"), time-of-day distraction peaks, recurring rationalizations ("for inspiration").
4. **Real rhythms / windows** — when the user *actually* does each kind of work (true focus windows, energy dips) vs when they schedule it.
5. **Follow-through rates** — % of planned blocks that become real, sliced by domain / activity / time-of-day — and the conditions that raise or lower it.
6. **Second-order levers** — patterns about patterns the user can act on: "mornings that start with the gym have higher follow-through all day."

---

## 5. The quality bar for a *surfaced* insight

Before Togi shows an insight it must be:
- **Evidenced** — meets the minimum evidence threshold (§6).
- **Specific & quantified** — carries a number/frequency/time ("~90 min/day", "3 mornings running", "after 15:00").
- **Novel** — passes the Miss Test; not obvious from a single entry.
- **Actionable** — implies a concrete planning change (store it as `suggestion`).
- **Kind & neutral** — descriptive, never guilt-inducing.

---

## 6. The memory: shape + lifecycle ("a note that updates until you change")

Each insight is a row in the **insight memory** (small, current — distinct from the long-term raw archive).

| Field | What it is |
|---|---|
| id, user_id | keys |
| family | one of §4 |
| statement | the human one-liner shown to the user |
| metric | short tag ("+90 min/day", "3× this week", "before 11am") |
| suggestion | optional: the planning nudge it implies |
| evidence_count | how many supporting instances |
| evidence_window | date range the evidence spans |
| example_entry_ids | a few entries that prove it |
| confidence | 0–1 |
| status | `candidate` → `active` → `fading` → `retired` |
| first_seen, last_confirmed, updated_at | timestamps |

**Lifecycle (this is what "memory until it changes" means):**
- A new pattern with enough evidence becomes a **candidate**, then **active** once confirmed.
- Each confirming observation: `evidence_count++`, `last_confirmed = now`, confidence ↑.
- Contradicting data: confidence ↓; if it keeps not holding → **fading** → **retired**.
- **Retired ≠ deleted** — kept as history ("you used to…"), just not surfaced.
- User can tap **"not true"** → immediate retire (strongest signal).
- Only **active** insights surface; cap the surfaced set (e.g., top 5 by value) and `log` what was dropped.

**Look-back window:** analyze roughly the **last 2–3 weeks** so the memory reflects the *current* user, while the long-term archive stays separate for the data bank.

---

## 7. How it's produced (hybrid — code computes, AI phrases)

Don't make the LLM crunch raw rows; that's unreliable. Split the work:

1. **Code aggregates** (deterministic, cheap) the last ~2–3 weeks of plan + real into candidate stats per family: slip counts & substitutions, planned-vs-actual duration deltas, distraction co-occurrence by preceding activity & hour, follow-through rates by domain/activity/time-of-day, gym-morning correlations, etc.
2. **AI phrases & judges** — takes those stats **plus the existing memory** and: writes the human `statement`, applies the Miss Test + quality bar, ranks by value, and reconciles each against existing notes (confirm / update / contradict). Returns structured JSON only.
3. **Code enforces** the hard rules (§9): evidence thresholds, dedupe/merge, status transitions, schema validation, the surfaced-set cap, language safety.

---

## 8. The insight-extraction system prompt (paste into the LLM call)

```
You maintain a behavioral-insight memory for a personal time-clarity app. You receive:
(a) pre-computed STATS about the user's last ~2-3 weeks (plan vs real, slips, duration
deltas, distraction co-occurrence, follow-through by time-of-day), and
(b) the user's EXISTING insight memory (statements + status).

Your job: surface only insights the user would NOT notice on their own.

THE MISS TEST — an insight qualifies ONLY if the user couldn't see it from inside a single
day. Reject anything that just restates one check-in (e.g. "you scrolled 2h today" — they
logged it, they know). Favor patterns that are: emergent across days, relational (plan vs
real, activity→distraction, time→follow-through), quantified, counter to the user's
assumptions, and actionable.

For each qualifying pattern return: family (one of: drift, estimation, distraction, rhythm,
follow_through, second_order), a short human STATEMENT with a number/frequency in it, a
METRIC tag, an optional SUGGESTION (a concrete planning change), a CONFIDENCE 0-1, the
evidence_count it's based on, and a RECONCILE field: "new" | "confirms:<id>" |
"contradicts:<id>" against the existing memory.

Rules:
- Never restate a single event. Never moralize or guilt. Be warm and neutral.
- Be specific and quantified; no vague "be more productive".
- Prefer fewer, higher-value insights over many weak ones.
- If a stat is too thin to be sure, mark confidence low; code will hide it.

Return ONLY valid JSON: { "insights": [ {family, statement, metric, suggestion, confidence,
evidence_count, reconcile} ] }
```

---

## 9. Hard rules (enforced in code, not the prompt)

1. **Evidence floor:** never surface an insight whose pattern spans < 2 days OR < 3 instances. (This is the Miss Test in code — kills single-event "insights".)
2. **Dedupe/merge by (family, subject):** an incoming insight that matches an existing one *updates* it (evidence++, confidence, last_confirmed); it does not create a duplicate.
3. **Status transitions are code-controlled** (candidate/active/fading/retired) based on confirm/contradict counts — the LLM only suggests `reconcile`.
4. **Surfaced cap:** show at most N active insights (default 5), ranked by value; `log` anything dropped (no silent truncation).
5. **Language safety:** reject/regenerate statements that are judgmental.
6. **Schema validation:** every stored insight matches the §6 shape.

---

## 10. Worked examples — MISS vs NOT-MISS

- ❌ **Not an insight** (already known): "You scrolled 2h today instead of emailing." — single event, just logged.
- ✅ **Insight:** "Four days running, scrolling lands *inside* your planned editing blocks (~1h40 each), and the edit slides to after 3pm." — cross-day, relational, quantified, actionable.
- ❌ **Not an insight:** "You spent 45 min on errands."
- ✅ **Insight:** "Your errands run ~90 min/day longer than you plan — that's why your afternoons collapse." — systematic estimation error, cumulative, invisible per-trip.
- ❌ **Not an insight:** "You did deep work this morning."
- ✅ **Insight:** "Deep work only happens before 11am; nothing you schedule after lunch survives." — rhythm, counter-assumption, actionable.
- ✅ **Insight (second-order):** "On mornings that start with the gym, your follow-through the rest of the day is noticeably higher." — a lever the user can pull.

---

## 11. Analytics implication

Because domains are a fixed enum and activities are a controlled vocabulary (per the categorization spec), the §7 aggregations are reliable and cheap: group by domain/activity/time-of-day, diff plan vs real by the plan-id link, co-occur distraction against the preceding block. The memory sits on top of that as the curated, human-facing layer.
