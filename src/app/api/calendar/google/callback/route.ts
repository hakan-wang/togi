import { withUser } from "@/server/lib/api";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return withUser(request, async () => {
    const url = new URL(request.url);
    const code = url.searchParams.get("code");

    return {
      provider: "google",
      status: code ? "callback_received" : "missing_code"
    };
  });
}
