import { z } from "zod";
import { withUser } from "@/server/lib/api";
import { createGoogleCalendarService } from "@/server/services/calendar/calendar.service";

export const dynamic = "force-dynamic";

const calendar = createGoogleCalendarService();
const connectOutputSchema = z.object({
  provider: z.literal("google"),
  authorizationUrl: z.string().nullable(),
  status: z.enum(["ready", "not_configured"])
});

export async function GET(request: Request) {
  return withUser(request, async (userId) => {
    const authorizationUrl = calendar.createAuthorizationUrl(userId);

    return {
      provider: "google",
      authorizationUrl,
      status: authorizationUrl ? "ready" : "not_configured"
    };
  }, connectOutputSchema);
}
