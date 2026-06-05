import { withUser } from "@/server/lib/api";
import { services } from "@/server/services/container";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return withUser(request, (userId) => services.patterns.list(userId));
}
