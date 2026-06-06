# Runtime note: auth state, WebSocket streaming, and the HTTP fallback

Date: 2026-06-06
Status: Known behavior (not a blocker) + one optional optimization

## What we observed

In live testing the sidecar log (`~/Library/Logs/Bogi/sidecar.log`) showed `token=False`
on every request — i.e. the app was **not signed in** (no Supabase access token). Every model
turn therefore looked like:

```
gen mode=stream ...
stream FAILED: Unexpected server response: 401  fallback=True
✓ ok   (answered over HTTP)
```

The requests still succeeded — they answered correctly over the HTTP `/v1/infer` path — but
two things follow from being unsigned.

## Why this happens

- The WebSocket endpoint (`bogi-ws-backend`, `wss://spz67o2b6l.execute-api.eu-west-1.amazonaws.com/prod`)
  was deployed with **auth enforced** (Option B): `$connect` validates the Supabase token from
  `?token=`. With no/blank token, `$connect` returns **401** and the socket never opens.
- When the WS stream fails, `BogiProxyChatModel` **transparently falls back** to the
  (currently `AUTH_DISABLED=1`) HTTP `/v1/infer`, so the agent still answers.

## Impact

1. **No token-by-token streaming while unsigned.** Streaming only happens over the WebSocket;
   the HTTP fallback returns the whole reply at once. To get streaming you must **sign in** to
   Bogi so the app sends a valid token (`SidecarClient.tokenProvider` →
   `SupabaseAuth.currentAccessToken()`), which the WS `$connect` then accepts.
2. **A wasted round trip per turn while unsigned.** Each model turn attempts the WS connect,
   gets 401, then falls back — so every turn pays one doomed WS handshake before answering.

## How to get streaming

Sign in within the app. Then `token` is non-empty on each request frame, the WS `$connect`
succeeds, and replies stream token-by-token (rendered incrementally by `CoachView`).

## Optional optimization (not yet done)

Skip the WS attempt entirely when there is no token: in the sidecar, if the per-request token
is empty, go straight to the HTTP `post` instead of attempting (and failing) the WS connect.
This removes the wasted handshake for unsigned/dev usage. It's a pure latency optimization —
behavior is already correct via the fallback — so it was left out for now.

## Related deployment facts

- HTTP backend `bogi-backend` and WS backend `bogi-ws-backend` both run `AUTH_DISABLED`-aware
  handlers. **HTTP is currently `AUTH_DISABLED=1`** (open); **WS enforces auth** (Option B).
  This asymmetry is why unsigned requests fail WS but succeed HTTP.
- If auth is later enabled on the HTTP backend too (`AUTH_DISABLED=0`), unsigned usage will stop
  working entirely (the fallback would also 401), so the per-request fresh-token path
  (`SidecarClient.tokenProvider`) becomes mandatory — it is already wired.
