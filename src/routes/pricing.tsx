import { createFileRoute, Link } from "@tanstack/react-router";

export const Route = createFileRoute("/pricing")({
  head: () => ({
    meta: [{ title: "Togi | Pricing" }],
  }),
  component: Pricing,
});

type Plan = {
  name: string;
  price: string;
  period: string;
  tagline: string;
  features: string[];
  cta: string;
  featured: boolean;
};

// NOTE: plans + prices are placeholders until Michelle sends the real ones.
const PLANS: Plan[] = [
  {
    name: "Free",
    price: "0",
    period: "kr / mo",
    tagline: "Start seeing where your time actually goes.",
    features: [
      "Plan your day into blocks",
      "Log what you actually did",
      "This week and this month view",
    ],
    cta: "Get started",
    featured: false,
  },
  {
    name: "Pro",
    price: "XX",
    period: "kr / mo",
    tagline: "The full accountability loop and your data bank.",
    features: [
      "Everything in Free",
      "Your AI accountability coach",
      "Smart planning that learns your rhythm",
      "Long-term data bank and year in review",
    ],
    cta: "Get started",
    featured: true,
  },
];

function Pricing() {
  return (
    <div className="relative min-h-screen overflow-hidden px-6 py-16">
      <div className="sky-bg" aria-hidden="true" />

      <div className="relative z-10 mx-auto max-w-4xl">
        <div className="text-center">
          <Link
            to="/"
            className="text-xs uppercase tracking-[0.2em] text-muted-foreground hover:text-foreground"
            style={{ fontFamily: "var(--font-mono)" }}
          >
            back
          </Link>
          <h1
            className="mt-6 text-5xl tracking-tight text-foreground"
            style={{ fontFamily: "var(--font-serif)" }}
          >
            Simple pricing
          </h1>
          <p
            className="mx-auto mt-3 max-w-md text-lg text-muted-foreground"
            style={{ fontFamily: "var(--font-serif)" }}
          >
            Start free. Step up when you want the full loop.
          </p>
        </div>

        <div className="mt-12 grid gap-6 sm:grid-cols-2">
          {PLANS.map((plan) => (
            <div
              key={plan.name}
              data-featured={plan.featured}
              className="sharp-card flex flex-col p-8 text-left"
            >
              <p
                className="text-xs uppercase tracking-[0.2em] text-primary"
                style={{ fontFamily: "var(--font-mono)" }}
              >
                {plan.name}
              </p>
              <div className="mt-4 flex items-baseline gap-2">
                <span
                  className="text-5xl tracking-tight text-foreground"
                  style={{ fontFamily: "var(--font-serif)" }}
                >
                  {plan.price}
                </span>
                <span
                  className="text-sm text-muted-foreground"
                  style={{ fontFamily: "var(--font-mono)" }}
                >
                  {plan.period}
                </span>
              </div>
              <p
                className="mt-3 text-base text-muted-foreground"
                style={{ fontFamily: "var(--font-serif)" }}
              >
                {plan.tagline}
              </p>
              <ul className="mt-6 flex-1 space-y-2">
                {plan.features.map((f) => (
                  <li
                    key={f}
                    className="text-sm text-foreground/80"
                    style={{ fontFamily: "var(--font-serif)" }}
                  >
                    {f}
                  </li>
                ))}
              </ul>
              <Link
                to="/demo"
                className="sharp-btn mt-8 block w-full text-center"
                style={{ fontFamily: "var(--font-mono)" }}
              >
                {plan.cta}
              </Link>
            </div>
          ))}
        </div>

        <p
          className="mt-10 text-center text-xs text-muted-foreground/70"
          style={{ fontFamily: "var(--font-mono)" }}
        >
          Plans and prices are placeholders. Send me the real ones and I will drop them in.
        </p>
      </div>
    </div>
  );
}
