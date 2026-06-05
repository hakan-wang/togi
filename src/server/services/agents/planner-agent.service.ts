import type { AgentRunService } from "./agent-runs.service";
import type { PlannerAgentInput, PlannerAgentOutput } from "@/server/schemas/agents";
import { plannerAgentOutputSchema } from "@/server/schemas/agents";
import { runStructuredAgent, shouldUseOpenAiAgents } from "./agent-runtime";

const defaultModel = process.env.OPENAI_MODEL ?? "gpt-4.1-mini";

const inferCategory = (request: string) => {
  const value = request.toLowerCase();
  if (value.includes("work") || value.includes("draft") || value.includes("ship")) return "work";
  if (value.includes("exercise") || value.includes("run")) return "health";
  return "planning";
};

export const createPlannerAgentService = (runs: AgentRunService) => ({
  async plan(userId: string, input: PlannerAgentInput): Promise<PlannerAgentOutput> {
    return runs.record(userId, "planner", input, defaultModel, async () => {
      if (shouldUseOpenAiAgents()) {
        return runStructuredAgent({
          name: "Planner Agent",
          model: defaultModel,
          outputType: plannerAgentOutputSchema,
          input,
          instructions:
            "Convert user intention into checkable planned blocks. Reject vague productivity framing by making success criteria concrete. Use calendar availability exactly. Surface useful pattern warnings without therapy framing."
        });
      }

      const slot = input.calendarAvailability[0];
      const goal = input.activeGoals[0];
      const title = goal ? `Move ${goal.title} forward` : "Complete focused planning block";
      const pattern = input.userPatterns[0]?.recommendation;

      return {
        blocks: [
          {
            title,
            startTime: slot.startTime,
            endTime: slot.endTime,
            intentionText: goal
              ? `Make concrete progress on ${goal.title}: ${input.request}`
              : `Turn "${input.request}" into one visible deliverable`,
            successCriteria: [
              "Produce one concrete artifact or decision",
              "Write a short end-of-block status note"
            ],
            category: inferCategory(input.request)
          }
        ],
        coachingNote: pattern ? `Pattern to respect: ${pattern}` : "Plan made checkable; vague intention removed."
      };
    });
  }
});
