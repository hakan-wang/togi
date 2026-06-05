import { z } from "zod";
import { parseJson, withUser } from "@/server/lib/api";
import { services } from "@/server/services/container";

export const dynamic = "force-dynamic";

const coachInputSchema = z.object({
  question: z.string().trim().min(1)
});

export async function POST(request: Request) {
  return withUser(request, async (userId) => {
    const input = await parseJson(request, coachInputSchema);
    return services.coachAgent.coach(userId, input.question);
  });
}
