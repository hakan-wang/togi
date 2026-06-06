import { createFileRoute, Link } from "@tanstack/react-router";
import { useRef, useEffect } from "react";
import mascotImg from "@/assets/mascot.png";

export const Route = createFileRoute("/bogi")({
  head: () => ({
    meta: [
      { title: "Bogi · Take back control of your time" },
      {
        name: "description",
        content:
          "A private AI coach that helps you plan your day, then face what you actually did with it.",
      },
    ],
  }),
  component: BogiLanding,
});

function BogiLanding() {
  const glowRef = useRef<HTMLDivElement>(null);

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

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden px-6">
      {/* dreamy sky + drifting clouds */}
      <div className="sky-bg" aria-hidden="true" />
      {/* soft sunlight that follows the cursor */}
      <div ref={glowRef} className="glow" aria-hidden="true" />

      <div className="hero-in relative z-10 flex w-full max-w-md flex-col items-center text-center">
        <img
          src={mascotImg}
          alt="Bogi, the axolotl mascot"
          className="togi-hero float-soft relative z-20 -mb-12 h-48 w-48 object-contain sm:h-56 sm:w-56"
          draggable={false}
        />
        <div className="glass-hero relative z-10 w-full px-8 pb-9 pt-16">
          <h1
            className="text-4xl leading-[1.06] tracking-tight text-foreground sm:text-5xl"
            style={{ fontFamily: "var(--font-serif)" }}
          >
            Take back control of your time
          </h1>
          <p
            className="mx-auto mt-4 max-w-sm text-base leading-relaxed text-muted-foreground sm:text-lg"
            style={{ fontFamily: "var(--font-serif)" }}
          >
            A private AI coach that helps you plan your day, then face what you
            actually did with it.
          </p>
          <Link
            to="/pricing"
            className="apple-btn mt-7"
            style={{ fontFamily: "var(--font-grotesk)" }}
          >
            Get started
          </Link>
        </div>
      </div>
    </div>
  );
}
