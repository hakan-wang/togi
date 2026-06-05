import { parseJson, withUser } from "@/server/lib/api";
import { createPlannedBlockSchema } from "@/server/schemas/planned-blocks";
import { services } from "@/server/services/container";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return withUser(request, (userId) => services.plannedBlocks.list(userId));
}

export async function POST(request: Request) {
  return withUser(request, async (userId) => services.plannedBlocks.create(userId, await parseJson(request, createPlannedBlockSchema)));
}
