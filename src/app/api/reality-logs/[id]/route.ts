import { parseJson, withUser } from "@/server/lib/api";
import { updateRealityLogSchema } from "@/server/schemas/reality-logs";
import { services } from "@/server/services/container";

export const dynamic = "force-dynamic";

type Context = { params: Promise<{ id: string }> };

export async function GET(request: Request, context: Context) {
  const { id } = await context.params;
  return withUser(request, (userId) => services.realityLogs.get(userId, id));
}

export async function PATCH(request: Request, context: Context) {
  const { id } = await context.params;
  return withUser(request, async (userId) => services.realityLogs.update(userId, id, await parseJson(request, updateRealityLogSchema)));
}
