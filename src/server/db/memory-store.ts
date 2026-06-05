import type { TogiStore } from "./store";

export const createMemoryStore = (): TogiStore => ({
  goals: [],
  plannedBlocks: [],
  realityLogs: [],
  agentRuns: [],
  userPatterns: []
});

const globalMemoryStore = globalThis as typeof globalThis & {
  __togiMemoryStore?: TogiStore;
};

export const memoryStore = (globalMemoryStore.__togiMemoryStore ??= createMemoryStore());
