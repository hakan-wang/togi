import { task } from "@trigger.dev/sdk/v3";
import { createGoogleCalendarService } from "@/server/services/calendar/calendar.service";

const calendar = createGoogleCalendarService();

export const calendarSync = task({
  id: "calendar_sync",
  run: async (payload: { userId: string }) => calendar.syncChanges(payload.userId)
});
