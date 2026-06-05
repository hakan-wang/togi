import { createId } from "@/server/lib/ids";
import { notFound } from "@/server/lib/errors";
import { nowIso } from "@/server/lib/time";
import type { TogiStore } from "@/server/db/store";
import type { CreateRealityLogInput, RealityLog, UpdateRealityLogInput } from "@/server/schemas/reality-logs";

export const createRealityLogService = (store: TogiStore) => ({
  async list(userId: string): Promise<RealityLog[]> {
    return store.realityLogs.filter((log) => log.userId === userId);
  },

  async get(userId: string, id: string): Promise<RealityLog> {
    const log = store.realityLogs.find((item) => item.id === id && item.userId === userId);
    if (!log) throw notFound("reality log");
    return log;
  },

  async create(userId: string, input: CreateRealityLogInput): Promise<RealityLog> {
    const block = store.plannedBlocks.find((item) => item.id === input.plannedBlockId && item.userId === userId);
    if (!block) throw notFound("planned block");

    const timestamp = nowIso();
    const log: RealityLog = {
      id: createId(),
      userId,
      plannedBlockId: input.plannedBlockId,
      actualSummary: input.actualSummary,
      completionScore: input.completionScore,
      deviationReason: input.deviationReason,
      actualCategories: input.actualCategories,
      confirmedByUser: input.confirmedByUser,
      source: input.source,
      createdAt: timestamp,
      updatedAt: timestamp
    };
    store.realityLogs.push(log);
    return log;
  },

  async update(userId: string, id: string, input: UpdateRealityLogInput): Promise<RealityLog> {
    const log = await this.get(userId, id);
    Object.assign(log, input, { updatedAt: nowIso() });
    return log;
  }
});
