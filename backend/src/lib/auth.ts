/**
 * Shared authentication helper used by the authed routes. Honours the
 * AUTH_DISABLED local-dev escape hatch by returning a stub user without
 * touching Supabase.
 */
import { config } from "./config.js";
import { bearerToken } from "./http.js";
import { verifyJwt, type AuthUser } from "./supabase.js";

const DEV_USER: AuthUser = { id: "00000000-0000-0000-0000-000000000000", email: "dev@local" };

export async function authenticate(headers: Record<string, string | undefined>): Promise<AuthUser> {
  if (config.authDisabled) {
    return DEV_USER;
  }
  const token = bearerToken(headers);
  return verifyJwt(token);
}
