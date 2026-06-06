import { createFileRoute } from "@tanstack/react-router";
import { useRef, useEffect, useState, type FormEvent } from "react";
import { supabase } from "@/integrations/supabase/client";
import mascotImg from "@/assets/mascot.png";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Bogi · Take back control of your time" },
      {
        name: "description",
        content:
          "Bogi is almost here. A private AI coach that helps you plan your day, then face what you actually did with it. Join the waitlist.",
      },
    ],
  }),
  component: Waitlist,
});

function Waitlist() {
  const glowRef = useRef<HTMLDivElement>(null);
  const [email, setEmail] = useState("");
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let raf = 0;
    let pending: { x: number; y: number } | null = null;
    const apply = () => {
      raf = 0;
      const el = glowRef.current;
      if (el && pending) {
        el.style.setProperty("--mx", `${pending.x}px`);
        el.style.setProperty("--my", `${pending.y}px`);
      }
    };
    const onMove = (e: MouseEvent) => {
      pending = { x: e.clientX, y: e.clientY };
      if (!raf) raf = requestAnimationFrame(apply);
    };
    window.addEventListener("mousemove", onMove);
    return () => {
      window.removeEventListener("mousemove", onMove);
      if (raf) cancelAnimationFrame(raf);
    };
  }, []);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError("");
    const trimmed = email.trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) {
      setError("Please enter a valid email.");
      return;
    }
    setLoading(true);
    const { error: insertError } = await supabase
      .from("waitlist_signups")
      .insert({ email: trimmed });
    setLoading(false);
    if (insertError) {
      // unique violation: already on the list, treat as success
      if (insertError.code === "23505") {
        setSubmitted(true);
        return;
      }
      setError("Something went wrong. Please try again.");
      return;
    }
    setSubmitted(true);
  };

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden px-6">
      <div className="sky-bg" aria-hidden="true" />
      <div ref={glowRef} className="glow" aria-hidden="true" />

      <div className="hero-in relative z-10 flex w-full max-w-md flex-col items-center text-center">
        <img
          src={mascotImg}
          alt="Bogi, the axolotl mascot"
          className="togi-hero float-soft relative z-20 -mb-12 h-48 w-48 object-contain sm:h-56 sm:w-56"
          draggable={false}
        />
        <div className="glass-hero relative z-10 w-full px-8 pb-9 pt-16">
          <p
            className="mb-3 text-[0.7rem] font-medium uppercase tracking-[0.22em] text-primary"
            style={{ fontFamily: "var(--font-mono)" }}
          >
            Coming soon
          </p>
          <h1
            className="text-4xl leading-[1.06] tracking-tight text-foreground sm:text-5xl"
            style={{ fontFamily: "var(--font-serif)" }}
          >
            Take back control of your time
          </h1>

          {submitted ? (
            <p
              className="mx-auto mt-5 max-w-sm text-base leading-relaxed text-muted-foreground sm:text-lg"
              style={{ fontFamily: "var(--font-serif)" }}
            >
              You are on the list. We will email you the moment Bogi opens.
            </p>
          ) : (
            <>
              <p
                className="mx-auto mt-4 max-w-sm text-base leading-relaxed text-muted-foreground sm:text-lg"
                style={{ fontFamily: "var(--font-serif)" }}
              >
                Bogi is almost here. Leave your email and you will be first in
                line.
              </p>
              <form onSubmit={handleSubmit} className="mt-7 flex flex-col gap-3">
                <input
                  type="email"
                  required
                  maxLength={255}
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@email.com"
                  className="waitlist-input"
                  style={{ fontFamily: "var(--font-grotesk)" }}
                />
                <button
                  type="submit"
                  disabled={loading}
                  className="apple-btn w-full"
                  style={{ fontFamily: "var(--font-grotesk)" }}
                >
                  {loading ? "Joining..." : "Join the waitlist"}
                </button>
                {error && <p className="text-sm text-vermilion">{error}</p>}
              </form>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
