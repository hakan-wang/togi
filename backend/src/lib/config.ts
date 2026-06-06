/**
 * Centralised, lazily-read configuration. Everything comes from environment
 * variables — the backend stores no config of its own and ships no secrets.
 *
 * Reads are lazy (via getters) so that tests can mock individual values and so
 * that a missing variable only throws when the route that needs it runs, not
 * at module load time.
 */

function required(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === "") {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function optional(name: string, fallback: string): string {
  const value = process.env[name];
  return value === undefined || value === "" ? fallback : value;
}

export const config = {
  /** AWS region hosting the Bedrock model. */
  get bedrockRegion(): string {
    return optional("BEDROCK_REGION", "eu-central-1");
  },
  /** Bedrock model id used by default when a request omits `model`. */
  get bedrockModelId(): string {
    return optional("BEDROCK_MODEL_ID", "eu.anthropic.claude-sonnet-4-6");
  },
  get supabaseUrl(): string {
    return required("SUPABASE_URL");
  },
  /** Anon key — used only to verify a caller's JWT (no elevated access). */
  get supabaseAnonKey(): string {
    return required("SUPABASE_ANON_KEY");
  },
  /** Service-role key — used to read/write the `profiles` table (bypasses RLS). */
  get supabaseServiceKey(): string {
    return required("SUPABASE_SERVICE_KEY");
  },
  get stripeWebhookSecret(): string {
    return required("STRIPE_WEBHOOK_SECRET");
  },
  /**
   * Optional Stripe secret key. NOT required for webhook signature verification
   * (that only needs STRIPE_WEBHOOK_SECRET); kept optional for future API use.
   */
  get stripeSecretKey(): string {
    return optional("STRIPE_SECRET_KEY", "sk_unused_for_webhook_verification");
  },
  /**
   * Local-dev escape hatch. When set to "1"/"true", JWT verification and paid
   * checks are skipped. Default OFF — must never be enabled in production.
   */
  get authDisabled(): boolean {
    const value = process.env.AUTH_DISABLED;
    return value === "1" || value === "true";
  },
} as const;
