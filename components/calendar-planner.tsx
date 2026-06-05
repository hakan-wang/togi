"use client";

import { useState } from "react";

export function CalendarPlanner() {
  const [request, setRequest] = useState("");
  const [status, setStatus] = useState("idle");

  async function submitPlan() {
    setStatus("planning");
    const response = await fetch("/api/planner", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ userRequest: request, currentCalendar: [], relevantPatterns: [] })
    });
    setStatus(response.ok ? "planned" : "failed");
  }

  return (
    <section className="rounded-md border border-line bg-white p-4">
      <label className="text-sm font-medium" htmlFor="planner">What are you locking in on?</label>
      <textarea id="planner" className="mt-2 min-h-24 w-full rounded-md border border-line p-3" value={request} onChange={(event) => setRequest(event.target.value)} />
      <button className="mt-3 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button" onClick={submitPlan}>
        Plan block
      </button>
      <p className="mt-2 text-sm text-steel">{status}</p>
    </section>
  );
}
