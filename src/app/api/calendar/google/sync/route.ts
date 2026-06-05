import { z } from "zod";
import { withUser } from "@/server/lib/api";
import { createGoogleCalendarService } from "@/server/services/calendar/calendar.service";

export const dynamic = "force-dynamic";

const calendar = createGoogleCalendarService();
const syncOutputSchema = z.object({ synced: z.number().int().min(0) });

export async function POST(request: Request) {
  return withUser(request, (userId) => calendar.syncChanges(userId), syncOutputSchema);
}
