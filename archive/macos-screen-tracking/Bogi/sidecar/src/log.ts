import { appendFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

// Diagnostic log. Defaults to ~/Library/Logs/Bogi/sidecar.log; override with BOGI_LOG.
// Best-effort and never throws — diagnostics must not break the agent.
const LOG_PATH = process.env.BOGI_LOG || join(homedir(), "Library", "Logs", "Bogi", "sidecar.log");
let ready = false;

export function logLine(event: string, data?: unknown): void {
  try {
    if (!ready) { mkdirSync(dirname(LOG_PATH), { recursive: true }); ready = true; }
    const line = JSON.stringify({ t: new Date().toISOString(), event, data }) + "\n";
    appendFileSync(LOG_PATH, line);
  } catch {
    /* never let logging break anything */
  }
}
