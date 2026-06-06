# Google Calendar OAuth — Loopback Redirect for the macOS Desktop App

Date: 2026-06-06
Status: Approved direction, implementing
Supersedes: the reversed-client-ID custom-scheme redirect in `GoogleConfig` / `GoogleCalendarService`

## Problem

Connecting Google Calendar fails at the consent screen with:

```
Error 400: redirect_uri_mismatch
```

### Root cause

The app sends a **reversed-client-ID custom-scheme** redirect URI:

```
com.googleusercontent.apps.217551213798-…:/oauth2redirect
```

built in `GoogleCalendarService.authorize` (`redirectScheme:/oauth2redirect`) and mirrored in
`Packaging/Info.plist` (`CFBundleURLTypes`). That redirect style belongs to **iOS** OAuth clients.

But the credentials in `BackendConfig.GoogleConfig` carry a client **secret** (`GOCSPX-…`), which
only **Desktop** OAuth clients have. So the registered client is a *Desktop* client, and:

- Desktop clients **do not** support custom-scheme redirects at all, and
- Google has **removed custom URI schemes** as a supported redirect method (app-impersonation risk).

The redirect we send can never be registered on that client → `redirect_uri_mismatch`.

### What Google supports today (verified June 2026)

- **Custom URI schemes:** no longer supported.
- **OOB / copy-paste (`urn:ietf:wg:oauth:2.0:oob`):** no longer supported.
- **Loopback IP flow (`http://127.0.0.1:<port>`):** deprecated for iOS/Android/Chrome client
  types but **explicitly retained for Desktop client types** — and is Google's recommended path
  for desktop apps that can run a local web server.

Sources:
- https://developers.google.com/identity/protocols/oauth2/native-app
- https://developers.google.com/identity/protocols/oauth2/resources/loopback-migration
- https://developers.googleblog.com/making-google-oauth-interactions-safer-by-using-more-secure-oauth-flows/
- RFC 8252 (OAuth 2.0 for Native Apps): https://datatracker.ietf.org/doc/rfc8252/

## Decision

Keep Bogi a **macOS Desktop OAuth client** (clientID + secret unchanged) and switch the
authorization-capture mechanism from a custom-scheme `ASWebAuthenticationSession` to the
**loopback redirect flow**:

1. Start a local HTTP listener bound to `127.0.0.1` on an **ephemeral port** assigned by the OS.
2. Build `redirect_uri = http://127.0.0.1:<port>/oauth2redirect`.
3. Open Google's consent URL in the user's **default browser** (`NSWorkspace`).
4. Google redirects the browser to the loopback URL with `?code=…` (or `?error=…`); the listener
   reads the authorization code from the first HTTP request line and serves a small "you can close
   this tab" HTML page.
5. Exchange the code for tokens at the token endpoint **using the same `redirect_uri`**, the
   PKCE `code_verifier`, the clientID and the client secret. Tokens stay in the Keychain.

PKCE (S256) is kept exactly as-is — required regardless of redirect method, and the main defense
against code interception on the loopback interface.

### Why loopback over `localhost`

Per RFC 8252 and Google's guidance, `127.0.0.1` is preferred over `localhost`: it is not subject
to DNS, less likely to be blocked by client firewalls, and only reachable from the local device.
We bind IPv4 `127.0.0.1` and put that exact literal in the redirect URI. (Google requires the
authorization server to accept any port for loopback redirects, so no port is registered in the
Console.)

## Changes

### Code

- **New** `Infrastructure/Calendar/LoopbackOAuthListener.swift`
  - `NWListener` on `127.0.0.1`, port `0` (OS-assigned). Exposes the bound port.
  - `waitForCallback() async throws -> URL` — resumes when the browser hits the redirect, returning
    the full `http://127.0.0.1:<port><request-target>` URL for the caller to parse.
  - Pure, unit-testable helper `requestTarget(fromHTTPRequest:)` that extracts the request target
    (path + query) from a raw HTTP request's first line (`GET /oauth2redirect?code=… HTTP/1.1`).
  - Serves a minimal HTML response telling the user to return to Bogi, then cancels the listener.

- **`GoogleCalendarService.swift`**
  - `authorize(clientId:clientSecret:)` — drop the `presentationAnchor`. Start the listener, build
    the loopback `redirect_uri`, open the auth URL in the browser (injectable `openURL` closure,
    defaulting to `NSWorkspace`), await the callback, extract `code`, exchange.
  - Remove `presentAuthSession`, the `PresentationContextProvider`, the `redirectScheme` stored
    property, and the `AuthenticationServices` import.

- **`BackendConfig.swift` (`GoogleConfig`)**
  - Keep `clientID` and `clientSecret` (Desktop client). Remove `redirectScheme`. Update comments.

- **`CalendarSyncCoordinator.swift`**
  - `connectGoogle()` — drop the anchor param and the `.regular` activation-policy promotion that
    existed only so an accessory app could present a web-auth sheet; with the system browser that is
    no longer required. Re-activate the app after the callback for good UX.

- **`CalendarsSettingsView.swift`**
  - Call `sync.connectGoogle()` with no anchor; drop the `AuthenticationServices` import and the
    `ASPresentationAnchor` construction.

### Config

- **`Packaging/Info.plist`** — remove the `CFBundleURLTypes` block (the custom scheme is unused).
- Entitlements: no change. Bogi is **not sandboxed**, so binding a loopback listener needs no
  `network.server` entitlement.

### Google Cloud Console

- No change required. The existing **Desktop** OAuth client already accepts `http://127.0.0.1:<port>`
  loopback redirects implicitly; no redirect URI needs to be registered.

## Testing

- Unit-test the pure `requestTarget(fromHTTPRequest:)` parser: well-formed `GET` line, query
  preserved, malformed input returns `nil`.
- Keep existing PKCE generation behavior covered.
- Full browser round-trip is validated manually (can't be unit-tested without a real browser).
