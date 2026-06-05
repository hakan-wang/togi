import type { AgentRunService } from "./agent-runs.service";
import type { RealityLogAgentInput, RealityLogAgentOutput } from "@/server/schemas/agents";
import { realityLogAgentOutputSchema } from "@/server/schemas/agents";
import { runStructuredAgent, shouldUseOpenAiAgents } from "./agent-runtime";

const defaultModel = process.env.OPENAI_MODEL ?? "gpt-4.1-mini";

const scoreAnswer = (answer: string, criteria: string[]) => {
  const lower = answer.toLowerCase();
  const completed = criteria.filter((criterion) => {
    const firstTerm = criterion.toLowerCase().split(/\s+/).find((word) => word.length > 3);
    return firstTerm ? lower.includes(firstTerm) : false;
  }).length;
  if (lower.includes("did not") || lower.includes("didn't")) {
    return Math.max(0.1, completed / Math.max(criteria.length, 1) - 0.1);
  }
  return Math.min(1, Math.max(0.1, completed / Math.max(criteria.length, 1)));
};

export const createRealityLogAgentService = (runs: AgentRunService) => ({
  async draft(userId: string, input: RealityLogAgentInput): Promise<RealityLogAgentOutput> {
    return runs.record(userId, "reality_log", input, defaultModel, async () => {
      if (shouldUseOpenAiAgents()) {
        return runStructuredAgent({
          name: "Reality Log Agent",
          model: defaultModel,
          outputType: realityLogAgentOutputSchema,
          input,
          instructions:
            "Turn planned block plus user answer into a structured reality log draft. Score against success criteria, not generic productivity. User confirmation is final truth, so return confirmedByUser false."
        });
      }

      const completionScore = scoreAnswer(input.userAnswer, input.plannedBlock.successCriteria);
      const needsClarification = input.userAnswer.trim().length < 12;

      return {
        actualSummary: input.userAnswer,
        completionScore,
        actualCategories: [input.plannedBlock.title.toLowerCase().includes("draft") ? "writing" : "execution"],
        deviationReason: completionScore >= 1 ? "" : "User answer indicates at least one success criterion was missed.",
        clarificationQuestion: needsClarification ? "What exactly got finished, and what did not?" : null,
        confirmedByUser: false
      };
    });
  }
});
