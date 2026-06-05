import { withUser } from "@/server/lib/api";
import { createGoogleCalendarService } from "@/server/services/calendar/calendar.service";

export const dynamic = "force-dynamic";

const calendar = createGoogleCalendarService();

export async function GET(request: Request) {
  return withUser(request, async (userId) => {
    const authorizationUrl = calendar.createAuthorizationUrl(userId);

    return {
      provider: "google",
      authorizationUrl,
      status: authorizationUrl ? "ready" : "not_configured"
    };
  });
}
