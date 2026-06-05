import type { FastifyInstance } from "fastify";
import { RealityLogSyncSchema } from "../schemas/sync.js";

export async function registerSyncRoutes(server: FastifyInstance) {
  server.post("/sync/reality-logs", async (request, reply) => {
    RealityLogSyncSchema.parse(request.body);
    return reply.code(202).send({ accepted: true });
  });
}
