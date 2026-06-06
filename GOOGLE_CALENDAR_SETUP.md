# Connecting Togi to Google Calendar

The code is finished. Togi can book voice-scheduled events straight into a user's Google
Calendar over the official API. The only thing the app can't generate itself is a Google OAuth
**client id** — that has to be created once in the Google Cloud Console. This is that 5-minute step.

## What's already built (no action needed)

- `GoogleCalendarService` — full sign-in (OAuth PKCE, no client secret), token refresh, and
  create / list / delete events. Tokens live only in the Mac Keychain, never on a server.
- `CalendarRouter` — books to Google when connected, otherwise falls back to Apple Calendar, and
  routes Undo back to whichever calendar the event went to.
- Settings → **Calendars** tab — paste the client id, click **Connect Google Calendar**, done.

## The one manual step: create the OAuth client id

1. Go to <https://console.cloud.google.com> and create (or pick) a project.
2. **APIs & Services → Library →** search "Google Calendar API" → **Enable**.
3. **APIs & Services → OAuth consent screen**:
   - User type: **External**.
   - Add the scope `https://www.googleapis.com/auth/calendar`.
   - While the app is in "Testing", add the Google accounts you want to test with as **Test users**
     (otherwise sign-in is blocked). Publishing later removes that limit.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   - Application type: **iOS** (this is the type that uses a custom URL-scheme redirect, which is
     what the app's sign-in flow expects — *not* "Desktop", which wants a localhost redirect).
   - Bundle ID: `com.bogi.app`
   - Create, then copy the **Client ID** (looks like `1234567890-abcdef.apps.googleusercontent.com`).

## Plug it into Togi

Open Togi → **Settings → Calendars**:

- **OAuth client id**: paste the client id from step 4.
- **redirect scheme**: set this to the *reversed* client id, i.e. drop the
  `.apps.googleusercontent.com` and prefix with `com.googleusercontent.apps.`:
  `com.googleusercontent.apps.1234567890-abcdef`
  (This is the redirect scheme Google issues for an iOS-type client. If you ever switch client
  types, match this field to whatever redirect that client uses.)
- Click **save**, then **Connect Google Calendar**. A Google sign-in sheet appears; approve it.
  The tab should then show "connected to google calendar".

From then on, "togi, book lunch with sara tomorrow at noon" creates the event directly in Google.

## Alternative with zero setup

If you don't want to create a client id at all, Togi still books events — into **Apple Calendar**.
If the user has added their Google account inside the Mac's **Calendar app** (System Settings →
Internet Accounts), those events sync up to Google anyway. The direct connection above is the
cleaner experience because it needs no manual Calendar-app setup from each user.

## For env-based / CI config

Instead of the Settings UI you can set `GOOGLE_CLIENT_ID` (and optionally
`GOOGLE_REDIRECT_SCHEME`) as environment variables; they take precedence over the stored settings.
