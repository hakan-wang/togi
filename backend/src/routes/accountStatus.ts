/**
 * GET /v1/account/status
 *
 * verify Supabase JWT → return { paid, plan } for the authed user.
 */
import type { APIGatewayProxyEventV2 } from "aws-lambda";
import { authenticate } from "../lib/auth.js";
import { config } from "../lib/config.js";
import { json, type HttpResponse } from "../lib/http.js";
import { getProfile } from "../lib/supabase.js";

export async function handleAccountStatus(event: APIGatewayProxyEventV2): Promise<HttpResponse> {
  const user = await authenticate(event.headers);

  if (config.authDisabled) {
    return json(200, { paid: true, plan: "dev" });
  }

  const profile = await getProfile(user.id);
  return json(200, { paid: profile.paid, plan: profile.plan });
}
