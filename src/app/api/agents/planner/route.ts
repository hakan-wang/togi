import { parseJson, withUser } from "@/server/lib/api";
import { plannerAgentInputSchema, plannerAgentOutputSchema } from "@/server/schemas/agents";
import { services } from "@/server/services/container";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withUser(request, async (userId) => services.plannerAgent.plan(userId, await parseJson(request, plannerAgentInputSchema)), plannerAgentOutputSchema);
}
