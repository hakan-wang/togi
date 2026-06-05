import type { FastifyInstance } from "fastify";
import { buildGoogleCalendarAuthUrl } from "../services/googleCalendarOAuth.js";

export async function registerGoogleCalendarRoutes(server: FastifyInstance) {
  server.get("/google-calendar/auth-url", async (request) => {
    const query = request.query as { clientId: string; redirectUri: string; state: string };
    return {
      url: buildGoogleCalendarAuthUrl(query).toString()
    };
  });
}
