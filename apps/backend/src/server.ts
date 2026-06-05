import Fastify from "fastify";

export function buildServer() {
  const server = Fastify({ logger: true });

  server.get("/health", async () => {
    return { ok: true };
  });

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = buildServer();
  await server.listen({ port: 3000, host: "0.0.0.0" });
}
