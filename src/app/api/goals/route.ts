import { createGoalSchema } from "@/server/schemas/goals";
import { services } from "@/server/services/container";
import { parseJson, withUser } from "@/server/lib/api";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return withUser(request, (userId) => services.goals.list(userId));
}

export async function POST(request: Request) {
  return withUser(request, async (userId) => services.goals.create(userId, await parseJson(request, createGoalSchema)));
}
