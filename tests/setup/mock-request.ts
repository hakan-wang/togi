export function jsonRequest(body: unknown): Request {
  return new Request("http://127.0.0.1/test", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
}
