/* ============================================================
   Togi design-system primitives used by the session overlay.
   Ported from the Claude Design _ds bundle (MessageBubble, Composer).
   ============================================================ */
"use client";
import * as React from "react";

export function MessageBubble({ from = "coach", children, thinking = false }:
  { from?: "coach" | "user"; children?: React.ReactNode; thinking?: boolean }) {
  const isUser = from === "user";
  const base: React.CSSProperties = {
    maxWidth: "78%",
    borderRadius: "var(--radius-bubble)",
    padding: "var(--space-8) var(--space-12)",
    font: "var(--weight-regular) var(--size-body)/1.4 var(--font-body)",
    color: isUser ? "var(--on-primary)" : "var(--text-strong)",
    background: isUser ? "var(--color-primary)" : "var(--surface-reply)",
    border: isUser ? "none" : "1px solid var(--glass-border-soft)",
    boxShadow: isUser ? "none" : "var(--shadow-bubble)",
    WebkitFontSmoothing: "antialiased",
  };
  if (thinking) {
    return (
      <div style={{ display: "flex", justifyContent: "flex-start" }}>
        <div style={base}><span style={{ color: "var(--muted)", font: "var(--weight-regular) var(--size-caption)/1.3 var(--font-body)" }}>togi is thinking…</span></div>
      </div>
    );
  }
  return (
    <div style={{ display: "flex", justifyContent: isUser ? "flex-end" : "flex-start", paddingLeft: isUser ? 32 : 0, paddingRight: isUser ? 0 : 32 }}>
      <div style={base}>{children}</div>
    </div>
  );
}

export function Composer({ value, onChange, onSend, placeholder = "talk to togi…" }:
  { value: string; onChange: (v: string) => void; onSend: () => void; placeholder?: string }) {
  const sendable = !!value && value.trim().length > 0;
  const handleKey = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); if (sendable) onSend(); }
  };
  return (
    <div style={{ display: "flex", alignItems: "flex-end", gap: "var(--space-6)", background: "var(--glass-fill)", WebkitBackdropFilter: "var(--glass-blur-thin)", backdropFilter: "var(--glass-blur-thin)", border: "1px solid var(--glass-border)", borderRadius: "var(--radius-pill)", padding: "var(--space-7) var(--space-6) var(--space-7) var(--space-14)" }}>
      <textarea rows={1} value={value} placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)} onKeyDown={handleKey}
        style={{ flex: 1, resize: "none", border: "none", outline: "none", background: "transparent", font: "var(--weight-regular) var(--size-body)/1.4 var(--font-body)", color: "var(--text-strong)", padding: "4px 0", maxHeight: 72 }} />
      <button type="button" aria-label="send" onClick={() => sendable && onSend()} disabled={!sendable}
        style={{ flex: "0 0 auto", width: 28, height: 28, borderRadius: "var(--radius-circle)", border: "none", background: sendable ? "var(--color-primary)" : "rgba(90,84,80,0.35)", color: "#fff", cursor: sendable ? "pointer" : "default", display: "inline-flex", alignItems: "center", justifyContent: "center" }}>
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="19" x2="12" y2="5" /><polyline points="5 12 12 5 19 12" /></svg>
      </button>
    </div>
  );
}
