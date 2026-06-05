import { memoryStore } from "@/server/db/memory-store";
import { createServerSupabaseClient } from "@/server/db/supabase";
import { createSupabaseServices, shouldUseSupabaseStore } from "@/server/db/supabase-store";
import { createAgentRunService } from "@/server/services/agents/agent-runs.service";
import { createCoachAgentService } from "@/server/services/agents/coach-agent.service";
import { createPlannerAgentService } from "@/server/services/agents/planner-agent.service";
import { createRealityLogAgentService } from "@/server/services/agents/reality-log-agent.service";
import { createGoalService } from "@/server/services/goals/goals.service";
import { createPatternService } from "@/server/services/patterns/patterns.service";
import { createPlannedBlockService } from "@/server/services/planned-blocks/planned-blocks.service";
import { createRealityLogService } from "@/server/services/reality-logs/reality-logs.service";
import type { TogiStore } from "@/server/db/store";

export const createMemoryServices = (store: TogiStore) => {
  const agentRuns = createAgentRunService(store);
  return {
    store,
    goals: createGoalService(store),
    plannedBlocks: createPlannedBlockService(store),
    realityLogs: createRealityLogService(store),
    patterns: createPatternService(store),
    agentRuns,
    plannerAgent: createPlannerAgentService(agentRuns),
    realityLogAgent: createRealityLogAgentService(agentRuns),
    coachAgent: createCoachAgentService(
      {
        listRealityLogs: async (userId) => store.realityLogs.filter((log) => log.userId === userId)
      },
      agentRuns
    )
  };
};

const memoryServices = createMemoryServices(memoryStore);

export const createServices = () => {
  const client = createServerSupabaseClient();
  if (client && shouldUseSupabaseStore(process.env)) {
    return createSupabaseServices(client);
  }
  return memoryServices;
};

export const services = createServices();
