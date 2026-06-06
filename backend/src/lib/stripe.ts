/**
 * Stripe webhook signature verification. `constructEvent` is a pure HMAC check
 * over the raw request body using STRIPE_WEBHOOK_SECRET, so no API key or
 * network access is required here.
 */
import Stripe from "stripe";
import { config } from "./config.js";

let stripe: Stripe | null = null;

function getStripe(): Stripe {
  if (!stripe) {
    // The secret key is unused for signature verification but the constructor
    // requires a value; a real key is only needed if we later call the API.
    stripe = new Stripe(config.stripeSecretKey);
  }
  return stripe;
}

/**
 * Verify the `stripe-signature` header against the raw payload and return the
 * parsed event. Throws if the signature is missing or invalid.
 */
export function constructEvent(payload: string | Buffer, signature: string | undefined): Stripe.Event {
  if (!signature) {
    throw new Error("Missing stripe-signature header");
  }
  return getStripe().webhooks.constructEvent(payload, signature, config.stripeWebhookSecret);
}

export type { Stripe };
