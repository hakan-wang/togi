export type CalendarSyncEvent = {
  provider: "google";
  syncToken: string | null;
  changedEventIds: string[];
};

export function describeCalendarSync(event: CalendarSyncEvent) {
  return `${event.provider}:${event.changedEventIds.length}:${event.syncToken ?? "initial"}`;
}
