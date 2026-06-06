/**
 * Lambda Function URL entry point. A single handler dispatches on method + path.
 * Errors thrown by routes are mapped to status codes via the HttpError class;
 * anything unexpected becomes a 500. No request/response content is logged.
 */
import type { APIGatewayProxyEventV2 } from "aws-lambda";
import { errorResponse, HttpError, type HttpResponse } from "./lib/http.js";
import { handleAccountStatus } from "./routes/accountStatus.js";
import { handleInfer } from "./routes/infer.js";
import { handleStripeWebhook } from "./routes/stripeWebhook.js";

function route(method: string, path: string): ((e: APIGatewayProxyEventV2) => Promise<HttpResponse>) | null {
  // Normalise trailing slash (but keep root "/").
  const normalized = path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path;
  if (method === "POST" && normalized === "/v1/infer") return handleInfer;
  if (method === "GET" && normalized === "/v1/account/status") return handleAccountStatus;
  if (method === "POST" && normalized === "/v1/stripe/webhook") return handleStripeWebhook;
  return null;
}

export async function handler(event: APIGatewayProxyEventV2): Promise<HttpResponse> {
  const method = event.requestContext?.http?.method ?? "";
  const path = event.rawPath ?? "";

  const matched = route(method, path);
  if (!matched) {
    return errorResponse(404, "Not found");
  }

  try {
    return await matched(event);
  } catch (err) {
    if (err instanceof HttpError) {
      return errorResponse(err.statusCode, err.message);
    }
    // Deliberately generic: never leak internals, never log content.
    console.error("Unhandled error", err instanceof Error ? err.message : "unknown");
    return errorResponse(500, "Internal server error");
  }
}
