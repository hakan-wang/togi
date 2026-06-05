import { parseJson, withUser } from "@/server/lib/api";
import { goalSchema, updateGoalSchema } from "@/server/schemas/goals";
import { services } from "@/server/services/container";

export const dynamic = "force-dynamic";

type Context = { params: Promise<{ id: string }> };

export async function PATCH(request: Request, context: Context) {
  const { id } = await context.params;
  return withUser(request, async (userId) => services.goals.update(userId, id, await parseJson(request, updateGoalSchema)), goalSchema);
}
