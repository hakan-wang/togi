import { memoryStore } from "@/server/db/memory-store";
import { createAgentRunService } from "@/server/services/agents/agent-runs.service";
import { createCoachAgentService } from "@/server/services/agents/coach-agent.service";
import { createPlannerAgentService } from "@/server/services/agents/planner-agent.service";
import { createRealityLogAgentService } from "@/server/services/agents/reality-log-agent.service";
import { createGoalService } from "@/server/services/goals/goals.service";
import { createPatternService } from "@/server/services/patterns/patterns.service";
import { createPlannedBlockService } from "@/server/services/planned-blocks/planned-blocks.service";
import { createRealityLogService } from "@/server/services/reality-logs/reality-logs.service";

const agentRuns = createAgentRunService(memoryStore);

export const services = {
  store: memoryStore,
  goals: createGoalService(memoryStore),
  plannedBlocks: createPlannedBlockService(memoryStore),
  realityLogs: createRealityLogService(memoryStore),
  patterns: createPatternService(memoryStore),
  agentRuns,
  plannerAgent: createPlannerAgentService(agentRuns),
  realityLogAgent: createRealityLogAgentService(agentRuns),
  coachAgent: createCoachAgentService(memoryStore, agentRuns)
};
