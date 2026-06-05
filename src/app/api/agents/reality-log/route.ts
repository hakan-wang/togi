import { parseJson, withUser } from "@/server/lib/api";
import { realityLogAgentInputSchema } from "@/server/schemas/agents";
import { services } from "@/server/services/container";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return withUser(request, async (userId) => services.realityLogAgent.draft(userId, await parseJson(request, realityLogAgentInputSchema)));
}
