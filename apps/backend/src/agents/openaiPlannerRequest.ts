type PlannerRequestInput = {
  userQuestion: string;
  retrievedContext: string;
};

export function buildOpenAIPlannerRequest(input: PlannerRequestInput) {
  return {
    model: "gpt-4.1",
    input: [
      "You are Bogi, a planning and reality-log coach.",
      "Use only Bogi-owned tools.",
      "Do not request raw continuous screen data.",
      "Ground advice in retrieved summaries, reality logs, planned blocks, and patterns.",
      `Retrieved context: ${input.retrievedContext}`,
      `User question: ${input.userQuestion}`
    ].join("\n"),
    text: {
      format: {
        type: "json_schema",
        name: "bogi_planning_response",
        schema: {
          type: "object",
          additionalProperties: false,
          required: ["summary", "suggestedPlan", "evidence"],
          properties: {
            summary: { type: "string" },
            suggestedPlan: { type: "string" },
            evidence: {
              type: "array",
              items: { type: "string" }
            }
          }
        }
      }
    }
  } as const;
}
