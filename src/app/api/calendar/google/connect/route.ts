import { withUser } from "@/server/lib/api";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return withUser(request, async () => ({
    provider: "google",
    authorizationUrl: process.env.GOOGLE_CALENDAR_AUTH_URL ?? null,
    status: process.env.GOOGLE_CALENDAR_AUTH_URL ? "ready" : "not_configured"
  }));
}
