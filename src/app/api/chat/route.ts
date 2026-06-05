import { parseJson, withUser } from "@/server/lib/api";
import { runTogiChat } from "@/server/services/chat/langchain-agent";
import { chatRequestSchema, chatResponseSchema } from "@/server/services/chat/schemas";

export const dynamic = "force-dynamic";

/**
 * The single chat endpoint for the Togi user experience. It is a thin wrapper
 * around the LangChain createAgent() service: parse the request, run the agent
 * for the authenticated user, and return the validated chat response.
 */
export async function POST(request: Request) {
  return withUser(
    request,
    async (userId) => {
      const { message, threadId } = await parseJson(request, chatRequestSchema);
      return runTogiChat({ userId, message, threadId });
    },
    chatResponseSchema
  );
}
