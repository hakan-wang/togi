import { withUser } from "@/server/lib/api";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return withUser(request, async () => ({
    provider: "google",
    status: "callback_received"
  }));
}
