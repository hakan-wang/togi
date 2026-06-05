import { json } from "@/server/lib/api";

export const dynamic = "force-dynamic";

export async function GET() {
  return json({ ok: true, service: "togi-backend" });
}
