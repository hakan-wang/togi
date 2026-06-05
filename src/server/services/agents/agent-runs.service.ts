import { createId } from "@/server/lib/ids";
import { nowIso } from "@/server/lib/time";
import type { TogiStore } from "@/server/db/store";
import type { AgentRun } from "@/server/schemas/agents";

export const createAgentRunService = (store: TogiStore) => ({
  async list(userId: string): Promise<AgentRun[]> {
    return store.agentRuns.filter((run) => run.userId === userId);
  },

  async record<T>(userId: string, agentName: string, inputJson: unknown, model: string, run: () => Promise<T>): Promise<T> {
    const agentRun: AgentRun = {
      id: createId(),
      userId,
      agentName,
      inputJson,
      outputJson: null,
      status: "started",
      error: null,
      model,
      startedAt: nowIso(),
      completedAt: null
    };
    store.agentRuns.push(agentRun);

    try {
      const output = await run();
      agentRun.outputJson = output;
      agentRun.status = "completed";
      agentRun.completedAt = nowIso();
      return output;
    } catch (error) {
      agentRun.status = "failed";
      agentRun.error = error instanceof Error ? error.message : "Unknown error";
      agentRun.completedAt = nowIso();
      throw error;
    }
  }
});

export type AgentRunService = ReturnType<typeof createAgentRunService>;
