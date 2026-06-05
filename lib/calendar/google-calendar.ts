import { google } from "googleapis";
import type { z } from "zod";
import type { plannedBlockSchema } from "@/lib/zod/contracts";

type PlannedBlockInput = z.infer<typeof plannedBlockSchema>;

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
