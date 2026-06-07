/* ============================================================
   Togi — Google Calendar server-side OAuth 2.0 (authorization code flow).
   Server-only module (never import from a client component).

   What it does:
   - Builds the Google consent URL with a signed `state` carrying the Togi user id.
   - Exchanges the auth code for access + refresh tokens.
   - Stores tokens per-user in Supabase (refresh_token encrypted at rest, AES-256-GCM),
     in the RLS-locked google_calendar_connections table (service_role only).
   - Returns a valid access token on demand, refreshing transparently when expired.

   Required env (apps/web/.env.local):
     GOOGLE_CLIENT_ID        (or reuse NEXT_PUBLIC_GOOGLE_CLIENT_ID)
     GOOGLE_CLIENT_SECRET
     GOOGLE_REDIRECT_URI     (optional — defaults to `${origin}/api/google/callback`)
     TOKEN_ENC_KEY           (any long random string — encrypts tokens + signs state)
     NEXT_PUBLIC_SUPABASE_URL
     SUPABASE_SERVICE_KEY
   ============================================================ */
// NOTE: server-only module. Import this ONLY from API route handlers (app/api/**),
// never from a "use client" component — it reads server secrets (client secret, service key).
import crypto from "node:crypto";
import { createClient, SupabaseClient } from "@supabase/supabase-js";

// Read + write the user's calendar events, list their calendars, and learn their email.
export const GOOGLE_SCOPES = [
  "https://www.googleapis.com/auth/calendar.events",
  "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
  "openid",
  "email",
].join(" ");

const GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
const GOOGLE_REVOKE_URL = "https://oauth2.googleapis.com/revoke";
const GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v2/userinfo";

/* ---------- config ---------- */
export function googleConfigured(): boolean {
  return !!(clientId() && process.env.GOOGLE_CLIENT_SECRET && process.env.TOKEN_ENC_KEY);
}
function clientId(): string {
  return process.env.GOOGLE_CLIENT_ID || process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID || "";
}
function clientSecret(): string {
  const s = process.env.GOOGLE_CLIENT_SECRET;
  if (!s) throw new Error("GOOGLE_CLIENT_SECRET is not set");
  return s;
}
export function redirectUri(origin: string): string {
  return process.env.GOOGLE_REDIRECT_URI || `${origin}/api/google/callback`;
}
function encKey(): Buffer {
  const raw = process.env.TOKEN_ENC_KEY;
  if (!raw) throw new Error("TOKEN_ENC_KEY is not set");
  return crypto.createHash("sha256").update(raw).digest(); // 32 bytes
}

/* ---------- token encryption at rest (AES-256-GCM) ---------- */
function encrypt(plain: string): string {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", encKey(), iv);
  const enc = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString("base64")}.${tag.toString("base64")}.${enc.toString("base64")}`;
}
function decrypt(blob: string): string {
  const [ivB, tagB, dataB] = blob.split(".");
  const decipher = crypto.createDecipheriv("aes-256-gcm", encKey(), Buffer.from(ivB, "base64"));
  decipher.setAuthTag(Buffer.from(tagB, "base64"));
  return Buffer.concat([decipher.update(Buffer.from(dataB, "base64")), decipher.final()]).toString("utf8");
}

/* ---------- signed OAuth state (HMAC, CSRF + carries the user id) ---------- */
export function signState(userId: string): string {
  const payload = `${userId}.${Date.now()}`;
  const sig = crypto.createHmac("sha256", encKey()).update(payload).digest("base64url");
  return Buffer.from(`${payload}.${sig}`).toString("base64url");
}
export function verifyState(state: string): string | null {
  try {
    const decoded = Buffer.from(state, "base64url").toString("utf8");
    const i = decoded.lastIndexOf(".");
    const payload = decoded.slice(0, i);
    const sig = decoded.slice(i + 1);
    const expect = crypto.createHmac("sha256", encKey()).update(payload).digest("base64url");
    if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expect))) return null;
    const [userId, ts] = payload.split(".");
    if (Date.now() - Number(ts) > 10 * 60 * 1000) return null; // 10 min window
    return userId || null;
  } catch { return null; }
}

/* ---------- Supabase admin (service_role; bypasses RLS) ---------- */
let _admin: SupabaseClient | null | undefined;
function admin(): SupabaseClient {
  if (_admin === undefined) {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const key = process.env.SUPABASE_SERVICE_KEY;
    _admin = url && key ? createClient(url, key, { auth: { persistSession: false } }) : null;
  }
  if (!_admin) throw new Error("Supabase service key not configured (SUPABASE_SERVICE_KEY).");
  return _admin;
}

/** Verify the Supabase access token sent by the browser → return the user id. */
export async function userIdFromRequest(req: Request): Promise<string | null> {
  const auth = req.headers.get("authorization") || req.headers.get("x-bogi-authorization") || "";
  const token = auth.toLowerCase().startsWith("bearer ") ? auth.slice(7) : "";
  if (!token) return null;
  try {
    const { data, error } = await admin().auth.getUser(token);
    if (error || !data.user) return null;
    return data.user.id;
  } catch { return null; }
}

/* ---------- OAuth: build consent URL ---------- */
export function buildConsentUrl(userId: string, origin: string): string {
  const params = new URLSearchParams({
    client_id: clientId(),
    redirect_uri: redirectUri(origin),
    response_type: "code",
    scope: GOOGLE_SCOPES,
    access_type: "offline",   // ask for a refresh token
    prompt: "consent",        // force refresh-token issuance on re-connect
    include_granted_scopes: "true",
    state: signState(userId),
  });
  return `${GOOGLE_AUTH_URL}?${params.toString()}`;
}

/* ---------- OAuth: exchange code → tokens, then persist ---------- */
interface TokenResponse {
  access_token: string; refresh_token?: string; expires_in: number; scope?: string; token_type: string;
}

export async function exchangeCodeAndStore(code: string, userId: string, origin: string): Promise<void> {
  const res = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: clientId(),
      client_secret: clientSecret(),
      redirect_uri: redirectUri(origin),
      grant_type: "authorization_code",
    }),
  });
  if (!res.ok) throw new Error(`Token exchange failed (${res.status}): ${await res.text()}`);
  const tok = (await res.json()) as TokenResponse;

  let email: string | null = null;
  try {
    const ui = await fetch(GOOGLE_USERINFO_URL, { headers: { Authorization: `Bearer ${tok.access_token}` } });
    if (ui.ok) email = (await ui.json()).email ?? null;
  } catch { /* email is best-effort */ }

  const row: Record<string, any> = {
    user_id: userId,
    google_email: email,
    access_token: encrypt(tok.access_token),
    expires_at: new Date(Date.now() + tok.expires_in * 1000).toISOString(),
    scope: tok.scope ?? GOOGLE_SCOPES,
  };
  // Only overwrite the refresh token if Google returned a new one (it omits it on
  // re-consent sometimes — keep the existing one in that case).
  if (tok.refresh_token) row.refresh_token = encrypt(tok.refresh_token);

  const { error } = await admin().from("google_calendar_connections").upsert(row, { onConflict: "user_id" });
  if (error) throw new Error(`Storing connection failed: ${error.message}`);
}

/* ---------- connection status / disconnect ---------- */
export async function getConnection(userId: string): Promise<{ google_email: string | null } | null> {
  const { data } = await admin()
    .from("google_calendar_connections")
    .select("google_email")
    .eq("user_id", userId)
    .maybeSingle();
  return data ?? null;
}

export async function disconnect(userId: string): Promise<void> {
  const { data } = await admin()
    .from("google_calendar_connections")
    .select("refresh_token, access_token")
    .eq("user_id", userId)
    .maybeSingle();
  // best-effort revoke at Google
  const enc = data?.refresh_token || data?.access_token;
  if (enc) {
    try {
      await fetch(GOOGLE_REVOKE_URL, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ token: decrypt(enc) }),
      });
    } catch { /* ignore */ }
  }
  await admin().from("google_calendar_connections").delete().eq("user_id", userId);
}

/* ---------- get a valid access token (refresh when expired) ---------- */
export async function getValidAccessToken(userId: string): Promise<string | null> {
  const { data } = await admin()
    .from("google_calendar_connections")
    .select("access_token, refresh_token, expires_at")
    .eq("user_id", userId)
    .maybeSingle();
  if (!data) return null;

  const expMs = new Date(data.expires_at).getTime();
  if (expMs - Date.now() > 60_000) return decrypt(data.access_token); // still fresh

  if (!data.refresh_token) return null; // can't refresh → caller treats as disconnected
  const res = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId(),
      client_secret: clientSecret(),
      refresh_token: decrypt(data.refresh_token),
      grant_type: "refresh_token",
    }),
  });
  if (!res.ok) {
    // refresh token revoked/expired → drop the dead connection
    if (res.status === 400 || res.status === 401) {
      await admin().from("google_calendar_connections").delete().eq("user_id", userId);
    }
    return null;
  }
  const tok = (await res.json()) as TokenResponse;
  await admin().from("google_calendar_connections").update({
    access_token: encrypt(tok.access_token),
    expires_at: new Date(Date.now() + tok.expires_in * 1000).toISOString(),
  }).eq("user_id", userId);
  return tok.access_token;
}
