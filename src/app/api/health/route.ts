import { z } from "zod";
import { jsonValidated } from "@/server/lib/api";

export const dynamic = "force-dynamic";

export async function GET() {
  return jsonValidated(z.object({ ok: z.literal(true), service: z.literal("togi-backend") }), { ok: true, service: "togi-backend" });
}
