import { realityLogInputSchema } from "@/lib/zod/contracts";

export const realityLogCreateInput = realityLogInputSchema.extend({});
export const realityLogUpdateInput = realityLogInputSchema.extend({
  realityLogId: realityLogInputSchema.shape.plannedBlockId
});
