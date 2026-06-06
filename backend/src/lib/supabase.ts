/**
 * Supabase glue: verify a caller's JWT and read/write the `profiles` table.
 *
 * Two clients are used:
 *  - anon client  → `auth.getUser(jwt)` validates the Bearer token without
 *    needing the JWT signing secret (Supabase validates server-side).
 *  - admin client → uses the service-role key to read/update `profiles`,
 *    bypassing RLS. This is the only path allowed to flip `paid`.
 *
 * Clients are created lazily and cached so the module imports cleanly even when
 * env vars are absent (e.g. in unit tests that mock this module).
 */
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { config } from "./config.js";
import { UnauthorizedError } from "./http.js";

let anonClient: SupabaseClient | null = null;
let adminClient: SupabaseClient | null = null;

function getAnonClient(): SupabaseClient {
  if (!anonClient) {
    anonClient = createClient(config.supabaseUrl, config.supabaseAnonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return anonClient;
}

function getAdminClient(): SupabaseClient {
  if (!adminClient) {
    adminClient = createClient(config.supabaseUrl, config.supabaseServiceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return adminClient;
}

export interface AuthUser {
  id: string;
  email: string | null;
}

export interface Profile {
  paid: boolean;
  plan: string | null;
}

/** Validate a Supabase JWT and return the authenticated user. */
export async function verifyJwt(token: string): Promise<AuthUser> {
  const { data, error } = await getAnonClient().auth.getUser(token);
  if (error || !data?.user) {
    throw new UnauthorizedError("Invalid or expired token");
  }
  return { id: data.user.id, email: data.user.email ?? null };
}

/** Read a user's paid status. Missing row is treated as unpaid. */
export async function getProfile(userId: string): Promise<Profile> {
  const { data, error } = await getAdminClient()
    .from("profiles")
    .select("paid, plan")
    .eq("id", userId)
    .maybeSingle();
  if (error) {
    throw new Error(`Failed to read profile: ${error.message}`);
  }
  return {
    paid: data?.paid ?? false,
    plan: data?.plan ?? null,
  };
}

/** Set paid status for a user identified by Supabase user id. Idempotent. */
export async function setPaidByUserId(
  userId: string,
  paid: boolean,
  plan: string | null,
  stripeCustomerId?: string | null,
): Promise<void> {
  const patch: Record<string, unknown> = {
    paid,
    plan,
    updated_at: new Date().toISOString(),
  };
  if (stripeCustomerId) patch["stripe_customer_id"] = stripeCustomerId;

  const { error } = await getAdminClient().from("profiles").update(patch).eq("id", userId);
  if (error) {
    throw new Error(`Failed to update profile by id: ${error.message}`);
  }
}

/** Set paid status for a user identified by their Stripe customer id. Idempotent. */
export async function setPaidByCustomerId(
  stripeCustomerId: string,
  paid: boolean,
  plan: string | null,
): Promise<void> {
  const patch: Record<string, unknown> = {
    paid,
    plan,
    updated_at: new Date().toISOString(),
  };
  const { error } = await getAdminClient()
    .from("profiles")
    .update(patch)
    .eq("stripe_customer_id", stripeCustomerId);
  if (error) {
    throw new Error(`Failed to update profile by customer id: ${error.message}`);
  }
}
