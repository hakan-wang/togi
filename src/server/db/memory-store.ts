import type { TogiStore } from "./store";

export const createMemoryStore = (): TogiStore => ({
  goals: [],
  plannedBlocks: [],
  realityLogs: [],
  agentRuns: [],
  userPatterns: []
});

export const memoryStore = createMemoryStore();
