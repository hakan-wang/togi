export const dayEndedEvent = "day.ended";

export type DayEndedPayload = {
  userId: string;
  day: string;
};

export type SummaryWriter = {
  writeSummary(input: { userId: string; scope: "day"; date: string }): Promise<unknown>;
};

export async function handleDailySummary(payload: DayEndedPayload, deps: SummaryWriter) {
  const summary = await deps.writeSummary({ userId: payload.userId, scope: "day", date: payload.day });
  return {
    event: dayEndedEvent,
    scope: "day",
    summary
  };
}
