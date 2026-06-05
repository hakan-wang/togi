import { google } from "googleapis";
import type { z } from "zod";
import type { plannedBlockSchema } from "@/lib/zod/contracts";

type PlannedBlockInput = z.infer<typeof plannedBlockSchema>;
type CalendarLike = {
  events: {
    insert(input: { calendarId: string; requestBody: ReturnType<typeof toGoogleCalendarEvent> }): Promise<{ data: { id?: string | null } }>;
  };
};

export function toGoogleCalendarEvent(block: PlannedBlockInput) {
  return {
    summary: block.title,
    description: `Success criteria: ${block.successCriteria}\nCategory: ${block.category}`,
    start: { dateTime: block.start },
    end: { dateTime: block.end }
  };
}

export function createGoogleOAuthClient() {
  return new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_REDIRECT_URI
  );
}

export function createGoogleCalendarClient() {
  return google.calendar({ version: "v3", auth: createGoogleOAuthClient() });
}

export async function insertGoogleCalendarEvent(calendar: CalendarLike, block: PlannedBlockInput) {
  const response = await calendar.events.insert({
    calendarId: "primary",
    requestBody: toGoogleCalendarEvent(block)
  });
  return response.data.id ?? null;
}
