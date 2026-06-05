# macOS Distribution

Bogi ships outside the Mac App Store for beta distribution.

Required release checks:

- Build a signed app archive.
- Package the app into a DMG.
- Submit the DMG for Apple notarization.
- Staple the notarization ticket.
- Verify Gatekeeper accepts the DMG on a clean macOS account.

Required secrets:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- Developer ID Application certificate in the signing keychain.

Sparkle is added after the first notarized DMG flow works.
