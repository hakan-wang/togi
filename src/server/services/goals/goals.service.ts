import { createId } from "@/server/lib/ids";
import { notFound } from "@/server/lib/errors";
import { nowIso } from "@/server/lib/time";
import type { CreateGoalInput, Goal, UpdateGoalInput } from "@/server/schemas/goals";
import type { TogiStore } from "@/server/db/store";

export const createGoalService = (store: TogiStore) => ({
  async list(userId: string): Promise<Goal[]> {
    return store.goals.filter((goal) => goal.userId === userId);
  },

  async create(userId: string, input: CreateGoalInput): Promise<Goal> {
    const timestamp = nowIso();
    const goal: Goal = {
      id: createId(),
      userId,
      title: input.title,
      description: input.description ?? null,
      status: "active",
      createdAt: timestamp,
      updatedAt: timestamp
    };
    store.goals.push(goal);
    return goal;
  },

  async update(userId: string, id: string, input: UpdateGoalInput): Promise<Goal> {
    const goal = store.goals.find((item) => item.id === id && item.userId === userId);
    if (!goal) throw notFound("goal");

    Object.assign(goal, {
      ...input,
      description: input.description === undefined ? goal.description : input.description,
      updatedAt: nowIso()
    });
    return goal;
  }
});
