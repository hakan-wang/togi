"use client";

import { useState } from "react";

export function CoachPanel() {
  const [message, setMessage] = useState("");
  const [reply, setReply] = useState("");

  async function send() {
    const response = await fetch("/api/coach", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message, patterns: [], logs: [] })
    });
    const data = await response.json();
    setReply(String(data.message ?? ""));
  }

  return (
    <section className="rounded-md border border-line bg-white p-4">
      <h2 className="text-lg font-semibold">Coach</h2>
      <textarea className="mt-3 min-h-20 w-full rounded-md border border-line p-3" value={message} onChange={(event) => setMessage(event.target.value)} />
      <button className="mt-3 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button" onClick={send}>Ask Bogi</button>
      {reply ? <p className="mt-3 text-sm">{reply}</p> : null}
    </section>
  );
}
