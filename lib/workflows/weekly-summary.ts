export const weekEndedEvent = "week.ended";

export type WeekEndedPayload = {
  userId: string;
  weekStart: string;
};

export type WeeklySummaryWriter = {
  writeSummary(input: { userId: string; scope: "week"; date: string }): Promise<unknown>;
};

export async function handleWeeklySummary(payload: WeekEndedPayload, deps: WeeklySummaryWriter) {
  const summary = await deps.writeSummary({ userId: payload.userId, scope: "week", date: payload.weekStart });
  return {
    event: weekEndedEvent,
    scope: "week",
    summary
  };
}
