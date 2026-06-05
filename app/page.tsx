import Link from "next/link";

export default function HomePage() {
  return (
    <main className="min-h-screen bg-paper text-ink">
      <section className="mx-auto flex min-h-screen max-w-5xl flex-col justify-center px-6">
        <p className="text-sm font-semibold uppercase tracking-wide text-moss">Bogi</p>
        <h1 className="mt-4 max-w-3xl text-5xl font-semibold leading-tight">
          Plan your time, prove what happened, learn your real patterns.
        </h1>
        <div className="mt-8 flex gap-3">
          <Link className="rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" href="/dashboard">
            Open dashboard
          </Link>
          <Link className="rounded-md border border-line px-4 py-2 text-sm font-medium" href="/lock-in">
            Start lock-in
          </Link>
        </div>
      </section>
    </main>
  );
}
