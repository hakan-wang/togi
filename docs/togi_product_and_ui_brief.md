# Togi — Product Context & UI Brief

*This document is the single source of truth for what Togi is and what the UI must contain. Paste it into Claude Design, or any Claude chat, to give full context before designing or brainstorming the interface. The product and the assistant share one name: **Togi** (not Toby, Toggi, or Toggy).*

---

## 1. What Togi is, in one paragraph

Togi is a private, voice-first AI assistant and accountability coach, delivered as a web app. You talk to Togi like you talk to Siri. It helps you plan your day into a calendar, and then it helps you record what you actually did with each block. The product lives in the gap between those two things: what you intended versus what really happened. Every honest moment of recording becomes data, and that data is the real product. Short-term, it gives you clarity on where your day went. Long-term, it builds a behavioral record of your life that no other app has, which you can use to plan better and understand yourself.

---

## 2. The core value (read this carefully, the framing has shifted)

The headline is **not** "accountability." The headline is **clarity and data about how you actually spend your time.**

- **Short-term value:** behavioral data on your daily habits. Where did today actually go?
- **Long-term value:** a compounding context bank of your life, for yourself.

Accountability is no longer the product. Accountability is the **mechanism** we use to collect user input. The user talks to Togi to say what they spent their time on. Togi then categorizes, sub-categorizes, and describes it, and hands the user back clarity on how the day was spent.

The psychological anchor: **awareness is the first step to improving any habit.** You cannot fix what you cannot see. Togi makes your time visible, and that visibility is what enables change. (There is established behavioral-psychology support for awareness and self-monitoring as the first lever of behavior change; worth citing real studies when we market this.)

**The compressed positioning:**
Togi helps you plan your day, then helps you record the difference between what you said you'd do and what you actually did, turning that gap into a private behavioral data bank that helps you plan better over time.

---

## 3. The problem

Your plan and your reality are two different things, and nobody tracks the gap between them. Four kinds of people live this every day.

**Scenario 1 — You plan, and still lose the day (no ADHD).** Your calendar says: record 2 hours, edit 3 hours, meetings, emails. You do the first few, get tired, open your phone "for a second," and 45 minutes of your email hour is gone. But your calendar still says "answered emails," so future-you believes you did. The calendar lied. For people who actually use TikTok and Instagram it is worse: that "second" is never less than 45 minutes, almost always stolen from work or study.

**Scenario 2 — ADHD makes it the whole day.** You plan honestly: "Emails at 11." On the way to the desk you pass the laundry. "I'll just do that first." Then you're up, might as well vacuum. Then organize the desk. Every task is real and reasonable, and the entire email hour is gone. Not laziness. There is always something else to do and nothing pulls you back. By evening you genuinely don't know where the time went.

**Scenario 3 — You can't even remember.** Ask a Swedish teenager "what did you do today?" and most can't tell you. Ask about the weekend, maybe they remember one thing. Most people have no record of their own life. Some had real goals this month. Did they hit them? They don't actually know, because they have no honest picture of their hours.

**Scenario 4 — "Where did my time go?"** "I didn't even wake up late, but it feels like the day just started and it's already 5pm." Everyone recognizes this instantly. The day evaporates and you're left with an uneasy feeling and no data to explain it.

### Why this is not a screen-time app

Screen-time apps *block* you. You hit the limit, tap "add 15 minutes," keep scrolling, learn nothing. The wall changed nothing because you never had to think.

Togi does the opposite, and the friction is the point. It is not a bug that you have to go in and record your time. It is the whole feature. A real accountability coach does not silently watch your screen and log it for you. A real coach *asks* you: "What did you just spend that hour on?" The moment you answer, in your own words, you become mindful of what you actually did. That mindfulness is the product, not the blocking.

> "It's meant to have friction, like when I have to talk to a real accountability partner. I have to face what I did and reflect on it. Awareness is the first step to improvement." — Håkan Wang

---

## 4. How Togi works: the loop

1. **You plan** specific, concrete blocks into your calendar (this is your *intention*).
2. **A block ends**, and Togi checks in: did you do it? If yes, good. If not, what did you do instead, and why?
3. **Togi categorizes** your input and writes it to the reality side (this is what *actually happened*).
4. **Over time**, that data gives you clarity day to day, and a long-term behavioral record that makes your future planning smarter.

Planning and recording are not two separate features. They are one loop. The product is the gap between the two.

---

## 5. The two sides of the calendar (central UI concept)

Togi has two time views that must both live in the interface:

- **Plan** — your calendar of intentions. Forward-looking. The future. What you said you'd do.
- **Actual** — what you actually did. Backward-looking. The past. The recorded reality, categorized and color-coded.

> **Naming note:** the "reality checked calendar" needs a real name. Recommendation: call it **Actual** (so the two toggle labels are **Plan / Actual**, a clean and meaningful pairing borrowed from "plan vs actuals"). Strong alternatives: **Real** (punchier, more gen-z) or **Recap** (warmer, more narrative). Pick one and keep it consistent across the whole UI. This brief uses *Actual* throughout.

**The open UI decision (build variants to compare):**
- **Variant A — Two calendars side by side or as separate tabs.** Plan on one, Actual on the other. Clearest separation, but you lose the at-a-glance comparison.
- **Variant B — One calendar with a Plan / Actual toggle.** You look at the same day and flip between intention and reality. Strongest for *feeling* the gap, which is the emotional core of the product.
- **Variant C — One calendar, both overlaid.** Each block shows plan vs actual together (e.g., the planned block with the real outcome layered or diffed on top). Most powerful but hardest to design without clutter.

This is the most important thing to prototype. The whole product is "see the gap," so the view that makes the gap most visceral wins.

---

## 6. Core features (all must be represented in the UI)

### 6.1 The Plan / Actual calendar view
The heart of the app. Shows intention (Plan) and recorded reality (Actual). Blocks are categorized and color-coded so a glance tells you the shape of your day.

### 6.2 Togi, the assistant (voice-first, on the main screen)
The whole platform is built around the agent. Togi holds all the knowledge, data, and context. Togi must be present on the main screen.
- **Primary interaction is voice.** You talk to Togi. Default to speaking for simplicity.
- Togi can respond in chat as well as voice; both should be possible. Final response style is undecided, so keep it flexible.
- "Hey Togi" is the wake phrase, the same way you'd say "Hey Siri."

### 6.3 Check-in sessions (the input mechanism, our unique core)
This is how clarity and data actually get collected. A check-in is a short, voice-led moment where you tell Togi what you did.
- **Scheduled check-ins:** triggered at the end of a planned block. Togi integrates with your calendar, sees the blocks, and checks in when one ends (e.g., after a 2-hour editing block).
- **Reminders default ON, but toggleable.** Our users downloaded Togi *because* they want this data, so most want the reminder. Most people would otherwise forget to check in. A user can turn it off, but it stays on by default.
- **Optional call-to-check-in:** the user can toggle on having Togi *call* them when it's time. If they don't answer, it falls back to a notification ("Don't forget to update Togi, it's check-in time").
- **Manual check-ins for blank time:** calendars have gaps with no scheduled blocks (2-3 empty hours). The user can self-report what happened in those gaps so Togi can still map and categorize the time (e.g., "I went to the gym"). The user can also opt into an hourly reminder during blank stretches.
- Each check-in is a 2-minute conversation. Low effort, high payoff.

A note on philosophy: do not nag like a screen-time app with a hundred notifications. The people who download Togi want to log their time. The reminders exist as a helpful nudge, not a guilt machine.

### 6.4 Planning sessions
Dedicated planning, run as short sessions with Togi (think of a 5-minute check-in with an accountability coach or a quick therapy-style sit-down).
- Run them the evening before, or the same morning.
- The user speaks freely about what they want to do, and Togi helps structure it into the calendar.
- **Togi coaches for specificity.** The product only works if intentions are concrete. The user cannot say "be productive." Togi pushes them to "edit videos for 1 hour" or "email manufacturers for 45 minutes," because a vague intention can't be checked and turns every block into a feeling of failure.
- **Togi categorizes the plan as it's made.** If the user says "tomorrow I want to edit video for 2 hours, answer emails for 45 minutes, clean my room for 1 hour, hang with friends, go to the cinema for 2 hours, and formulate Litro for 1.5 hours," Togi doesn't just list it. It categorizes each item and probes for clarity: "Answer emails, to whom?" → "Suppliers." Every planned block comes out concrete and categorized.

### 6.5 Categorization engine (backend, must be built)
Every input, both plans and check-ins, gets automatically categorized into three levels:
- **Category** — the broad bucket (e.g., *Activity with friends*, *Productive work*, *Health*).
- **Sub-category** — the specific recurring activity (e.g., *Jumpyard*, *Working on Litro*).
- **Description** — the detail of what actually happened (e.g., *emailing co-manufacturers*).
Togi reuses labels consistently so the data stays comparable over time. This categorization is the thing to build now (the full dashboard can come later, but categorization is foundational).

### 6.6 The data bank / dashboard (long-term analytics — its own page, NOT the main screen)
A separate dashboard/analytics page where you extract and explore your long-term data. This is *not* a main-screen feature; the main screen stays clean and consumer-focused.
- **Time ranges:** view a week, a month, a 3-month period, or a year.
- **Filter and sort:** by Work, Friends, Leisure, Productive, etc.
- **Ask Togi in natural language:** "Show me all my productive hours over the last six months," or "Show me every time I scrolled and tell me when I scrolled the most." Togi answers with real analytics.
- **Proactive insight:** Togi can surface patterns on its own, e.g., "Håkan loves scrolling TikTok when he's editing videos, because he's trying to pull inspiration from TikTok, and it pulls him in for two hours."
- **Export / second brain:** the long-term database can be handed to an AI for life recommendations and richer context about what you're working on and how you work.

### 6.7 Discrepancy tracking (planned but not done)
There will always be a gap between plan and reality. Togi notes what you planned but didn't do.
- Next time you plan, Togi reminds you with a list: "Here are things you've planned before but haven't managed to do."
- This must be visible in the UI.
- The user can **delete** an item, or tell Togi to **keep / reschedule** it ("count it, I still want it done").

---

## 7. Beta features (on the roadmap, NOT building today)

- **Project planning.** Add a larger project (e.g., "work on Togi") that spans a month, and Togi helps schedule the work for it across your calendar.
- **Behavioral training for future planning.** Togi learns from your history. If you've repeatedly failed to realize a 3-hour editing plan, Togi takes that into account in the next planning session and helps you set a plan you'll actually hit. Built on the short-term behavior database (habits/patterns) plus the long-term life database (context).

---

## 8. Who it's for

Students and normal people, starting in Sweden. Not corporate. People with or without ADHD. If you ask most teenagers what they did yesterday, most remember one thing and blank on the rest. Togi is for everyone who wants their time back and wants to actually see how they spend their life.

---

## 9. UI requirements summary (checklist for the designer)

**Main screen must have:**
- Togi present and reachable by voice ("Hey Togi"), front and center.
- The Plan / Actual calendar view (intention + recorded reality). This is the centerpiece; prototype Variants A, B, and C from section 5.
- Access to upcoming and scheduled sessions (planning sessions and check-ins).
- Easy entry into a check-in or planning session (e.g., tapping the next day in the calendar could auto-open a Togi planning session: "What do you want to do? Togi, help me plan.").
- A visible surface for discrepancies (planned-but-not-done), with delete / keep actions.

**Separate pages / tabs (not on the main screen):**
- The long-term data bank / dashboard with analytics, time-range selection, filtering, and natural-language querying of Togi.

**Interaction principles:**
- Voice-first, chat-optional.
- Friction is intentional but minimal: a check-in is ~2 minutes of talking.
- Reminders default on, fully toggleable, never naggy.
- Clean, consumer-grade, not a dense productivity dashboard. The main screen is calm; depth lives in tabs.

**Tabs will be necessary** — not everything fits on one screen. Suggested structure: Main (Togi + Plan/Actual calendar + sessions), Plan, Actual, Data/Insights, Settings.
