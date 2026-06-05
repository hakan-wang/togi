import { createId } from "@/server/lib/ids";
import { badRequest, notFound } from "@/server/lib/errors";
import { nowIso } from "@/server/lib/time";
import type { TogiStore } from "@/server/db/store";
import type { CreatePlannedBlockInput, PlannedBlock, UpdatePlannedBlockInput } from "@/server/schemas/planned-blocks";

const vaguePhrases = new Set(["be productive", "work", "focus", "catch up", "do stuff"]);

export const assertCheckablePlannedBlock = (input: Pick<CreatePlannedBlockInput, "title" | "intentionText" | "successCriteria">) => {
  const intention = input.intentionText.trim().toLowerCase();
  const title = input.title.trim().toLowerCase();
  if (vaguePhrases.has(intention) || vaguePhrases.has(title) || input.successCriteria.length === 0) {
    throw badRequest("planned block must be checkable");
  }
};

export const createPlannedBlockService = (store: TogiStore) => ({
  async list(userId: string): Promise<PlannedBlock[]> {
    return store.plannedBlocks.filter((block) => block.userId === userId);
  },

  async get(userId: string, id: string): Promise<PlannedBlock> {
    const block = store.plannedBlocks.find((item) => item.id === id && item.userId === userId);
    if (!block) throw notFound("planned block");
    return block;
  },

  async create(userId: string, input: CreatePlannedBlockInput): Promise<PlannedBlock> {
    assertCheckablePlannedBlock(input);
    const timestamp = nowIso();
    const block: PlannedBlock = {
      id: createId(),
      userId,
      calendarEventId: input.calendarEventId ?? null,
      title: input.title,
      startTime: input.startTime,
      endTime: input.endTime,
      intentionText: input.intentionText,
      successCriteria: input.successCriteria,
      category: input.category,
      status: "planned",
      createdBy: input.createdBy,
      createdAt: timestamp,
      updatedAt: timestamp
    };
    store.plannedBlocks.push(block);
    return block;
  },

  async update(userId: string, id: string, input: UpdatePlannedBlockInput): Promise<PlannedBlock> {
    const block = await this.get(userId, id);
    const merged = { ...block, ...input };
    assertCheckablePlannedBlock({
      title: merged.title,
      intentionText: merged.intentionText,
      successCriteria: merged.successCriteria
    });
    Object.assign(block, input, { updatedAt: nowIso() });
    return block;
  },

  async delete(userId: string, id: string): Promise<void> {
    const index = store.plannedBlocks.findIndex((item) => item.id === id && item.userId === userId);
    if (index === -1) throw notFound("planned block");
    store.plannedBlocks.splice(index, 1);
  }
});
