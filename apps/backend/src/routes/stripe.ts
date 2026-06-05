import type { FastifyInstance } from "fastify";

export async function registerStripeRoutes(server: FastifyInstance) {
  server.post("/stripe/webhook", async (_request, reply) => {
    return reply.code(202).send({ accepted: true });
  });
}
