import type { AgentRunService } from "./agent-runs.service";
import type { RealityLog } from "@/server/schemas/reality-logs";

const defaultModel = process.env.OPENAI_MODEL ?? "gpt-4.1-mini";

export const createCoachAgentService = (logs: { listRealityLogs(userId: string): Promise<RealityLog[]> }, runs: AgentRunService) => ({
  async coach(userId: string, question: string) {
    return runs.record(userId, "coach", { question }, defaultModel, async () => {
      const recentLogs = (await logs.listRealityLogs(userId)).slice(-5);
      const average =
        recentLogs.length === 0 ? null : recentLogs.reduce((sum, log) => sum + log.completionScore, 0) / recentLogs.length;

      return {
        answer:
          average === null
            ? "No reality logs yet. Make one checkable plan, then log what happened."
            : `Your recent completion average is ${average.toFixed(2)}. Plan smaller blocks until this improves.`,
        evidence: recentLogs.map((log) => ({ id: log.id, completionScore: log.completionScore }))
      };
    });
  }
});
