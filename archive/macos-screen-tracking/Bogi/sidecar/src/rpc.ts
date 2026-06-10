export type Inbound =
  | { kind: "chat"; id: string; threadId: string; text: string; token?: string }
  | { kind: "plan"; id: string; threadId: string; text: string; token?: string }
  | { kind: "judge"; id: string; threadId: string; text: string; token?: string }
  | { kind: "action_result"; id: string; ok: boolean; result?: unknown; message?: string };

export type Outbound =
  | { kind: "ready" }
  | { kind: "token"; id: string; text: string }
  | { kind: "result"; id: string; ok: boolean; text: string }
  | { kind: "action_call"; id: string; callId: string; name: string; input: unknown }
  | { kind: "error"; id: string; message: string };

export function encodeMessage(msg: Outbound): string {
  return JSON.stringify(msg) + "\n";
}

export class LineDecoder {
  private buf = "";
  constructor(private onMessage: (msg: Inbound) => void) {}
  push(chunk: string): void {
    this.buf += chunk;
    let nl: number;
    while ((nl = this.buf.indexOf("\n")) >= 0) {
      const line = this.buf.slice(0, nl).trim();
      this.buf = this.buf.slice(nl + 1);
      if (line) this.onMessage(JSON.parse(line) as Inbound);
    }
  }
}
