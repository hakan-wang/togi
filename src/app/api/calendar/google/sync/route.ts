import { withUser } from "@/server/lib/api";
import { createGoogleCalendarService } from "@/server/services/calendar/calendar.service";

export const dynamic = "force-dynamic";

const calendar = createGoogleCalendarService();

export async function POST(request: Request) {
  return withUser(request, (userId) => calendar.syncChanges(userId));
}
