/**
 * Tiny HTTP helpers for Lambda Function URL responses plus a small hierarchy of
 * typed errors that the router maps to status codes. Keeping this in one place
 * means routes can `throw new UnauthorizedError()` and stay readable.
 */

export interface HttpResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: string;
}

const JSON_HEADERS = { "content-type": "application/json" } as const;

export function json(statusCode: number, body: unknown): HttpResponse {
  return {
    statusCode,
    headers: { ...JSON_HEADERS },
    body: JSON.stringify(body),
  };
}

export function errorResponse(statusCode: number, message: string): HttpResponse {
  return json(statusCode, { error: message });
}

export class HttpError extends Error {
  readonly statusCode: number;
  constructor(statusCode: number, message: string) {
    super(message);
    this.name = new.target.name;
    this.statusCode = statusCode;
  }
}

export class BadRequestError extends HttpError {
  constructor(message = "Bad request") {
    super(400, message);
  }
}

export class UnauthorizedError extends HttpError {
  constructor(message = "Unauthorized") {
    super(401, message);
  }
}

/** Authenticated but no active subscription. */
export class PaymentRequiredError extends HttpError {
  constructor(message = "Payment required") {
    super(402, message);
  }
}

export class ForbiddenError extends HttpError {
  constructor(message = "Forbidden") {
    super(403, message);
  }
}

/** Extract a Bearer token from the Authorization header, case-insensitively. */
export function bearerToken(headers: Record<string, string | undefined>): string {
  const raw = headers["authorization"] ?? headers["Authorization"];
  if (!raw) throw new UnauthorizedError("Missing Authorization header");
  const match = /^Bearer\s+(.+)$/i.exec(raw.trim());
  if (!match || !match[1]) throw new UnauthorizedError("Malformed Authorization header");
  return match[1].trim();
}

/** Parse a JSON request body, throwing a 400 on malformed input. */
export function parseJsonBody<T>(body: string | undefined): T {
  if (!body) throw new BadRequestError("Empty request body");
  try {
    return JSON.parse(body) as T;
  } catch {
    throw new BadRequestError("Invalid JSON body");
  }
}
