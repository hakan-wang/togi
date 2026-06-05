import { parseJson, withUser } from "@/server/lib/api";
import { createRealityLogSchema } from "@/server/schemas/reality-logs";
import { services } from "@/server/services/container";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return withUser(request, (userId) => services.realityLogs.list(userId));
}

export async function POST(request: Request) {
  return withUser(request, async (userId) => services.realityLogs.create(userId, await parseJson(request, createRealityLogSchema)));
}
