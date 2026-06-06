/**
 * POST /v1/stripe/webhook
 *
 * Verify the Stripe signature against the raw body, then flip the user's paid
 * status in Supabase. Idempotent: re-delivering the same event simply re-applies
 * the same `paid`/`plan` values.
 */
import type { APIGatewayProxyEventV2 } from "aws-lambda";
import { json, type HttpResponse, UnauthorizedError } from "../lib/http.js";
import { constructEvent, type Stripe } from "../lib/stripe.js";
import { setPaidByCustomerId, setPaidByUserId } from "../lib/supabase.js";

/** Subscription statuses that count as an active, paid entitlement. */
const PAID_STATUSES: ReadonlySet<string> = new Set(["active", "trialing", "past_due"]);

function customerId(value: string | Stripe.Customer | Stripe.DeletedCustomer | null): string | null {
  if (!value) return null;
  return typeof value === "string" ? value : value.id;
}

function planFromSubscription(sub: Stripe.Subscription): string | null {
  const item = sub.items?.data?.[0];
  return item?.price?.id ?? null;
}

async function handleEvent(event: Stripe.Event): Promise<void> {
  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object as Stripe.Checkout.Session;
      // The website sets client_reference_id (preferred) or metadata to the
      // Supabase user id when creating the Checkout Session.
      const userId = session.client_reference_id ?? session.metadata?.["supabase_user_id"] ?? null;
      const plan = session.metadata?.["plan"] ?? null;
      const cust = customerId(session.customer);
      if (userId) {
        await setPaidByUserId(userId, true, plan, cust);
      } else if (cust) {
        await setPaidByCustomerId(cust, true, plan);
      }
      return;
    }
    case "customer.subscription.created":
    case "customer.subscription.updated": {
      const sub = event.data.object as Stripe.Subscription;
      const cust = customerId(sub.customer);
      if (cust) {
        await setPaidByCustomerId(cust, PAID_STATUSES.has(sub.status), planFromSubscription(sub));
      }
      return;
    }
    case "customer.subscription.deleted": {
      const sub = event.data.object as Stripe.Subscription;
      const cust = customerId(sub.customer);
      if (cust) {
        await setPaidByCustomerId(cust, false, null);
      }
      return;
    }
    default:
      // Ignore unrelated events; acknowledge with 200 so Stripe stops retrying.
      return;
  }
}

export async function handleStripeWebhook(event: APIGatewayProxyEventV2): Promise<HttpResponse> {
  const signature = event.headers["stripe-signature"] ?? event.headers["Stripe-Signature"];
  const payload = event.isBase64Encoded && event.body
    ? Buffer.from(event.body, "base64")
    : event.body ?? "";

  let stripeEvent: Stripe.Event;
  try {
    stripeEvent = constructEvent(payload, signature);
  } catch (err) {
    throw new UnauthorizedError(
      `Invalid Stripe signature: ${err instanceof Error ? err.message : "unknown"}`,
    );
  }

  await handleEvent(stripeEvent);
  return json(200, { received: true });
}
