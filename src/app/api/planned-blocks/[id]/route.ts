import { z } from "zod";
import { parseJson, withUser } from "@/server/lib/api";
import { plannedBlockSchema, updatePlannedBlockSchema } from "@/server/schemas/planned-blocks";
import { services } from "@/server/services/container";

export const dynamic = "force-dynamic";

type Context = { params: Promise<{ id: string }> };

export async function GET(request: Request, context: Context) {
  const { id } = await context.params;
  return withUser(request, (userId) => services.plannedBlocks.get(userId, id), plannedBlockSchema);
}

export async function PATCH(request: Request, context: Context) {
  const { id } = await context.params;
  return withUser(
    request,
    async (userId) => services.plannedBlocks.update(userId, id, await parseJson(request, updatePlannedBlockSchema)),
    plannedBlockSchema
  );
}

export async function DELETE(request: Request, context: Context) {
  const { id } = await context.params;
  return withUser(
    request,
    async (userId) => {
      await services.plannedBlocks.delete(userId, id);
      return { ok: true };
    },
    z.object({ ok: z.literal(true) })
  );
}
