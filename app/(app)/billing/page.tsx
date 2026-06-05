import { AppShell } from "@/components/app-shell";

export default function BillingPage() {
  return (
    <AppShell>
      <section className="max-w-2xl">
        <h1 className="text-3xl font-semibold">Founding plan</h1>
        <p className="mt-3 text-sm text-steel">Lifetime founding access for early Bogi users.</p>
        <button className="mt-6 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button">
          Join founding plan
        </button>
      </section>
    </AppShell>
  );
}
