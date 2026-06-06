import type { APIGatewayProxyEventV2 } from "aws-lambda";

/** Build a minimal Lambda Function URL (payload v2) event for tests. */
export function makeEvent(opts: {
  method: string;
  path: string;
  headers?: Record<string, string | undefined>;
  body?: string;
  isBase64Encoded?: boolean;
}): APIGatewayProxyEventV2 {
  return {
    version: "2.0",
    routeKey: "$default",
    rawPath: opts.path,
    rawQueryString: "",
    headers: opts.headers ?? {},
    requestContext: {
      http: {
        method: opts.method,
        path: opts.path,
        protocol: "HTTP/1.1",
        sourceIp: "127.0.0.1",
        userAgent: "vitest",
      },
    } as APIGatewayProxyEventV2["requestContext"],
    body: opts.body,
    isBase64Encoded: opts.isBase64Encoded ?? false,
  } as APIGatewayProxyEventV2;
}
