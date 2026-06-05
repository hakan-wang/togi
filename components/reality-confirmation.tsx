"use client";

import { useState } from "react";

export function RealityConfirmation({ plannedBlockId }: { plannedBlockId: string }) {
  const [correction, setCorrection] = useState("");
  const [status, setStatus] = useState("waiting");

  async function confirmReality() {
    setStatus("saving");
    const response = await fetch("/api/reality-log", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        plannedBlockId,
        plannedTitle: "Edit video",
        observationSummary: "Mostly editing, short YouTube drift.",
        userCorrection: correction
      })
    });
    setStatus(response.ok ? "confirmed" : "failed");
  }

  return (
    <section className="rounded-md border border-line bg-white p-4">
      <h2 className="text-lg font-semibold">Confirm reality</h2>
      <p className="mt-2 text-sm text-steel">Screen suggests mostly editing, with short drift. Accurate?</p>
      <textarea className="mt-3 min-h-24 w-full rounded-md border border-line p-3" value={correction} onChange={(event) => setCorrection(event.target.value)} />
      <button className="mt-3 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button" onClick={confirmReality}>
        Confirm log
      </button>
      <p className="mt-2 text-sm text-steel">{status}</p>
    </section>
  );
}
