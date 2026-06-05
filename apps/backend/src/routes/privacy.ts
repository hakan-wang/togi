import type { FastifyInstance } from "fastify";
import { buildPrivacyExport } from "../services/privacyExport.js";

export async function registerPrivacyRoutes(server: FastifyInstance) {
  server.get("/privacy/export/:userId", async (request) => {
    const params = request.params as { userId: string };
    return buildPrivacyExport(params.userId);
  });

  server.delete("/privacy/account/:userId", async (_request, reply) => {
    return reply.code(202).send({ accepted: true });
  });
}
