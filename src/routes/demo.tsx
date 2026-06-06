import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import mascotImg from "@/assets/mascot.png";

export const Route = createFileRoute("/demo")({
  head: () => ({ meta: [{ title: "Bogi · Demo" }] }),
  component: Demo,
});

type Status = "done" | "partial" | "missed";

const BLOCKS = [
  { time: "09:00 – 11:00", plan: "Edit the video", h: 2 },
  { time: "11:00 – 12:00", plan: "Email the makers", h: 1 },
  { time: "13:00 – 16:00", plan: "School work", h: 3 },
];

const FACTOR: Record<Status, number> = { done: 1, partial: 0.5, missed: 0 };
const REPLY: Record<Status, string> = {
  done: "Nice. Logged.",
  partial: "Honest. That still counts.",
  missed: "It happens. Now you know.",
};
const REALITY: Record<Status, string> = {
  done: "did all of it",
  partial: "did about half",
  missed: "did not get to it",
};

const fmt = (n: number) => (Number.isInteger(n) ? `${n}` : n.toFixed(1));

function Demo() {
  const [answers, setAnswers] = useState<Status[]>([]);
  const step = answers.length;
  const done = step >= BLOCKS.length;
  const current = BLOCKS[step];

  const planned = BLOCKS.reduce((s, b) => s + b.h, 0);
  const actual = answers.reduce((s, st, i) => s + BLOCKS[i].h * FACTOR[st], 0);
  const gap = Math.max(0, planned - actual);

  const reply = (s: Status) => setAnswers((a) => [...a, s]);

  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden px-6 py-12">
      <div className="sky-bg" aria-hidden="true" />

      <div className="relative z-10 w-full max-w-lg">
        <div className="flex items-end gap-3">
          <img
            src={mascotImg}
            alt="Bogi"
            className="h-20 w-20 shrink-0 object-contain monster-float"
            draggable={false}
          />
          <div className="demo-bubble mb-2">
            <p className="font-serif text-lg leading-snug text-foreground">
              {done ? (
                "Here is your day, honestly."
              ) : (
                <>
                  You planned to{" "}
                  <span className="italic">{current.plan.toLowerCase()}</span>. Did
                  you actually do it?
                </>
              )}
            </p>
          </div>
        </div>

        <div className="demo-card mt-5 p-6">
          {!done ? (
            <>
              <p
                className="mb-4 text-xs uppercase tracking-[0.18em] text-muted-foreground"
                style={{ fontFamily: "var(--font-mono)" }}
              >
                Today · {current.time}
              </p>
              <div className="space-y-2.5">
                {BLOCKS.map((b, i) => {
                  const st = answers[i];
                  const active = i === step;
                  return (
                    <div
                      key={b.time}
                      className={`flex items-center justify-between rounded-xl px-4 py-3 transition ${
                        active ? "bg-white/70 shadow-sm" : "bg-white/35"
                      }`}
                    >
                      <span className="font-serif text-base text-foreground">
                        {b.plan}
                      </span>
                      <span
                        className="text-xs text-muted-foreground"
                        style={{ fontFamily: "var(--font-mono)" }}
                      >
                        {st ? REALITY[st] : active ? "now" : `${b.h}h planned`}
                      </span>
                    </div>
                  );
                })}
              </div>

              <div className="mt-6 flex flex-col gap-2 sm:flex-row">
                <button
                  className="demo-choice demo-choice--primary"
                  onClick={() => reply("done")}
                >
                  Yes, all of it
                </button>
                <button className="demo-choice" onClick={() => reply("partial")}>
                  Some of it
                </button>
                <button className="demo-choice" onClick={() => reply("missed")}>
                  Not really
                </button>
              </div>

              {step > 0 && (
                <p
                  className="mt-4 text-sm text-muted-foreground"
                  style={{ fontFamily: "var(--font-mono)" }}
                >
                  {REPLY[answers[step - 1]]}
                </p>
              )}
            </>
          ) : (
            <>
              <p
                className="mb-4 text-xs uppercase tracking-[0.18em] text-muted-foreground"
                style={{ fontFamily: "var(--font-mono)" }}
              >
                Plan vs reality
              </p>
              <div className="space-y-4">
                {BLOCKS.map((b, i) => {
                  const f = FACTOR[answers[i]];
                  return (
                    <div key={b.time}>
                      <div className="flex items-baseline justify-between">
                        <span className="font-serif text-base text-foreground">
                          {b.plan}
                        </span>
                        <span
                          className="text-xs text-muted-foreground"
                          style={{ fontFamily: "var(--font-mono)" }}
                        >
                          {fmt(b.h * f)}h of {b.h}h
                        </span>
                      </div>
                      <div className="demo-bar mt-2">
                        <div
                          className="demo-bar-done"
                          style={{ width: `${f * 100}%` }}
                        />
                        <div
                          className="demo-bar-gap"
                          style={{ width: `${(1 - f) * 100}%` }}
                        />
                      </div>
                    </div>
                  );
                })}
              </div>

              <p className="mt-6 font-serif text-lg leading-snug text-foreground">
                You planned {fmt(planned)} hours and lived about {fmt(actual)} of
                them.{" "}
                {gap > 0
                  ? `The other ${fmt(gap)} slipped away, and now you can see where.`
                  : "You did everything you set out to do."}
              </p>

              <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:items-center">
                <Link
                  to="/pricing"
                  className="sharp-btn text-center"
                  style={{ fontFamily: "var(--font-mono)" }}
                >
                  Get started
                </Link>
                <button
                  className="text-sm text-muted-foreground transition-colors hover:text-foreground"
                  style={{ fontFamily: "var(--font-mono)" }}
                  onClick={() => setAnswers([])}
                >
                  Run it again
                </button>
              </div>
            </>
          )}
        </div>

        <div className="mt-6 text-center">
          <Link
            to="/bogi"
            className="text-sm text-muted-foreground transition-colors hover:text-foreground"
            style={{ fontFamily: "var(--font-mono)" }}
          >
            back
          </Link>
        </div>
      </div>
    </div>
  );
}
