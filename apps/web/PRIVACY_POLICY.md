# Togi — Privacy Policy (draft)

_Last updated: 6 June 2026. This is a starting draft — review with the specifics of your
deployment (company name, contact email, hosting region) before publishing._

## What Togi is
Togi is a personal time-clarity app that helps you compare your plan with your real day.

## Google user data we access
With your explicit consent, Togi requests these Google OAuth scopes:

- **See and edit events on your calendars** (`calendar.events`) — to show your real events on
  your Togi timeline and to let you create, edit, and delete events from inside Togi.
- **See the list of calendars you’re subscribed to** (`calendar.calendarlist.readonly`) — to
  know which calendars exist.
- **Your email address** (`openid`, `email`) — to label the connected account.

## How we use it
Your calendar data is used solely to provide the in-app calendar features described above. We
do **not** sell it, use it for advertising, or share it with third parties, and we do not use
it to train AI/ML models. Togi’s use of information from Google APIs adheres to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the Limited Use requirements.

## Storage and security
- OAuth tokens are stored on our server, encrypted at rest (AES-256-GCM), in a database row
  accessible only to the Togi backend (row-level security blocks all client access).
- Calendar event details are fetched on demand to render your timeline and are not retained
  beyond what’s needed to display them.

## Your choices
Disconnect at any time in **Settings → Disconnect**, which revokes Togi’s access at Google and
deletes the stored tokens. You can also revoke access at
<https://myaccount.google.com/permissions>.

## Contact
Questions or data requests: _<your-support-email>_.
