# Connect Google Calendar to Togi (read + edit, multi-user)

This is the **server-side OAuth** setup: tokens live on the server, refresh automatically,
and any user can connect *their own* Google Calendar — read their events and edit them
inside Togi.

It replaces the earlier browser-only "Client ID, no secret" approach. The difference:
you now also create a **Client Secret** and register a **redirect URI**.

---

## Part A — Google Cloud Console (~10 min, free)

1. **Sign in** at <https://console.cloud.google.com>.
2. **Create a project**: top-bar project dropdown → *New Project* → name it `Togi` → *Create* →
   make sure it's selected.
3. **Enable the API**: top search bar → "Google Calendar API" → *Enable*.
4. **OAuth consent screen** (left menu → *APIs & Services* → *OAuth consent screen*):
   - User type **External** → *Create*.
   - App name `Togi`, user support email = yours, developer email = yours → *Save and continue*.
   - **Scopes** → *Add or remove scopes* → add:
     - `.../auth/calendar.events`  (read **and write** events)
     - `.../auth/calendar.calendarlist.readonly`
     - `openid`, `email`
     → *Update* → *Save and continue*.
   - **Test users** → *Add users* → add every Gmail that should be able to connect **while
     the app is in Testing** (max 100, including your own). → *Save*.
     > ⚠️ In "Testing" status, ONLY these listed users can connect. To open it to the public,
     > see **Part C (verification)**.
5. **Create the OAuth client**: *APIs & Services* → *Credentials* → *+ Create credentials* →
   *OAuth client ID*:
   - Application type: **Web application**
   - Name: `Togi web`
   - **Authorized JavaScript origins** → add `http://localhost:3000`
   - **Authorized redirect URIs** → add `http://localhost:3000/api/google/callback`
     *(add your production URLs later, e.g. `https://app.togi.xyz` and
      `https://app.togi.xyz/api/google/callback`)*
   - *Create*.
6. A box pops up with **Client ID** *and* **Client secret**. Copy **both** (keep the secret
   private — do not paste it in chat or commit it).

---

## Part B — Put the values in Togi

In `apps/web/.env.local`:

```bash
GOOGLE_CLIENT_ID=xxxxxxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-xxxxxxxx
TOKEN_ENC_KEY=<run: openssl rand -base64 48>
# SUPABASE_SERVICE_KEY must also be set (Supabase → Project Settings → API → service_role key)
SUPABASE_SERVICE_KEY=eyJ...
```

Then apply the database table (Supabase → SQL editor, paste & run):
`backend/supabase/google_calendar.sql`

Restart the dev server (`npm run dev`). In Togi → **Settings → Connect Google Calendar**:
Google popup → allow → today's real events load into the **Plan** timeline. Tap the ✎ on any
Google block, or **Add event**, to edit your real calendar from inside Togi.

---

## Part C — Going public (OAuth verification)

So users *other than your test list* can connect, the app must move from **Testing → In
production** (consent screen → *Publish app*). Because calendar scopes are **sensitive**,
Google reviews the app first. You'll need:

- [ ] A **privacy policy** URL (draft in `PRIVACY_POLICY.md` — host it publicly).
- [ ] A **homepage** URL on the same verified domain.
- [ ] **Authorized domain** added on the consent screen + domain verified in
      [Google Search Console](https://search.google.com/search-console).
- [ ] App logo (120×120).
- [ ] A short **demo video** showing the OAuth consent + how each scope is used.
- [ ] Production redirect URIs registered on the OAuth client.

Submit via *OAuth consent screen → Publish app → Prepare for verification*. Review typically
takes a few days to a few weeks. Until it's approved, the public sees an "unverified app"
warning and only test users can complete the flow.

> Tip: keep using Testing mode for your beta (just add beta users to the test list), and
> submit for verification in parallel.
