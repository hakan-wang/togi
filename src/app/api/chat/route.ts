import { z } from "zod";
import { parseJson, withUser } from "@/server/lib/api";
import { realityLogAgentOutputSchema } from "@/server/schemas/agents";
import { goalSchema } from "@/server/schemas/goals";
import { plannedBlockSchema } from "@/server/schemas/planned-blocks";
import { realityLogSchema } from "@/server/schemas/reality-logs";
import { services } from "@/server/services/container";

export const dynamic = "force-dynamic";

const chatInputSchema = z.object({
  message: z.string().trim().min(1)
});

const chatOutputSchema = z.object({
  mode: z.enum(["planner", "reality_log", "coach"]),
  assistantMessage: z.string(),
  suggestions: z.array(z.string()),
  artifacts: z.object({
    plannedBlocks: z.array(plannedBlockSchema),
    realityDraft: realityLogAgentOutputSchema.nullable()
  }),
  state: z.object({
    goals: z.array(goalSchema),
    plannedBlocks: z.array(plannedBlockSchema),
    realityLogs: z.array(realityLogSchema)
  })
});

const planningPattern = /\b(plan|schedule|block|calendar|tomorrow|today|focus|make time)\b/i;
const realityPattern = /\b(done|did|finished|completed|happened|actually|logged|missed)\b/i;

const nextAvailability = () => {
  const start = new Date();
  start.setUTCMinutes(0, 0, 0);
  start.setUTCHours(start.getUTCHours() + 1);

  const end = new Date(start);
  end.setUTCHours(end.getUTCHours() + 1);

  return [{ startTime: start.toISOString(), endTime: end.toISOString() }];
};

const getState = async (userId: string) => ({
  goals: await services.goals.list(userId),
  plannedBlocks: await services.plannedBlocks.list(userId),
  realityLogs: await services.realityLogs.list(userId)
});

export async function POST(request: Request) {
  return withUser(request, async (userId) => {
    const input = await parseJson(request, chatInputSchema);
    const initialState = await getState(userId);

    if (planningPattern.test(input.message)) {
      const patterns = await services.patterns.list(userId);
      const plan = await services.plannerAgent.plan(userId, {
        request: input.message,
        calendarAvailability: nextAvailability(),
        activeGoals: initialState.goals
          .filter((goal) => goal.status === "active")
          .map((goal) => ({ id: goal.id, title: goal.title, status: goal.status })),
        userPatterns: patterns.map((pattern) => ({
          patternType: pattern.patternType,
          recommendation: pattern.recommendation,
          confidence: pattern.confidence
        }))
      });

      const plannedBlocks = [];
      for (const draft of plan.blocks) {
        plannedBlocks.push(
          await services.plannedBlocks.create(userId, {
            ...draft,
            calendarEventId: null,
            createdBy: "planner_agent"
          })
        );
      }

      return {
        mode: "planner",
        assistantMessage: `I planned ${plannedBlocks.length} checkable block${plannedBlocks.length === 1 ? "" : "s"}. ${plan.coachingNote}`,
        suggestions: ["Show me the plan", "Make it smaller", "What should I do first?"],
        artifacts: {
          plannedBlocks,
          realityDraft: null
        },
        state: await getState(userId)
      };
    }

    if (realityPattern.test(input.message) && initialState.plannedBlocks.length > 0) {
      const latestBlock = [...initialState.plannedBlocks].reverse()[0];
      const draft = await services.realityLogAgent.draft(userId, {
        plannedBlock: {
          id: latestBlock.id,
          title: latestBlock.title,
          intentionText: latestBlock.intentionText,
          successCriteria: latestBlock.successCriteria
        },
        userAnswer: input.message,
        historicalContext: initialState.realityLogs.slice(-3).map((log) => log.actualSummary)
      });

      return {
        mode: "reality_log",
        assistantMessage: `I drafted a reality log against "${latestBlock.title}" with a ${Math.round(
          draft.completionScore * 100
        )}% completion score. Confirm it before I treat it as truth.`,
        suggestions: ["Confirm this log", "Revise the summary", "Plan the next block"],
        artifacts: {
          plannedBlocks: [],
          realityDraft: draft
        },
        state: initialState
      };
    }

    const coach = await services.coachAgent.coach(userId, input.message);

    return {
      mode: "coach",
      assistantMessage: coach.answer,
      suggestions: ["Plan my next block", "What pattern do you see?", "Log what happened"],
      artifacts: {
        plannedBlocks: [],
        realityDraft: null
      },
      state: await getState(userId)
    };
  }, chatOutputSchema);
}
