import type { AgentRun } from "@/server/schemas/agents";
import type { Goal } from "@/server/schemas/goals";
import type { PlannedBlock } from "@/server/schemas/planned-blocks";
import type { RealityLog } from "@/server/schemas/reality-logs";
import type { UserPattern } from "@/server/schemas/patterns";

export type TogiStore = {
  goals: Goal[];
  plannedBlocks: PlannedBlock[];
  realityLogs: RealityLog[];
  agentRuns: AgentRun[];
  userPatterns: UserPattern[];
};
