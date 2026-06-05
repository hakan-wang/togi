import { z } from "zod";
import { withUser } from "@/server/lib/api";
import { userPatternSchema } from "@/server/schemas/patterns";
import { services } from "@/server/services/container";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return withUser(request, (userId) => services.patterns.list(userId), z.array(userPatternSchema));
}
