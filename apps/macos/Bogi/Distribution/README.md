# Bogi — distribution & release pipeline

This directory holds the [Sparkle](https://sparkle-project.org) appcast template
and documents how a Bogi release is built, signed, notarized, packaged, and
published for auto-update. All the moving parts are config/scripts — no secrets
are committed.

> Everything here runs on **macOS** (it uses `codesign`, `xcrun notarytool`,
> `hdiutil`, and Sparkle's `generate_keys` / `sign_update`). Devin develops on
> Linux, so these steps were authored and reviewed but not executed here.

## Prerequisites (one-time)

1. **Developer ID Application** certificate in your login keychain
   (`Developer ID Application: <Your Org> (TEAMID)`).
2. **Notary credentials**, stored once as a keychain profile:
   ```bash
   xcrun notarytool store-credentials bogi \
     --apple-id "you@example.com" --team-id "TEAMID" \
     --password "<app-specific-password>"
   ```
   (App Store Connect API keys and raw Apple-ID/password are also supported — see
   `scripts/macos/notarize.sh`.)
3. **Sparkle EdDSA signing keys** (used to sign updates so the installed app can
   verify them). Generate once with the `generate_keys` tool bundled in the
   Sparkle release:
   ```bash
   ./bin/generate_keys
   ```
   - The **private** key is stored in your login Keychain — **never commit it**.
   - The command prints the **public** key. Paste it into
     `apps/macos/Bogi/Resources/Info.plist` as `SUPublicEDKey` (replace the
     `REPLACE_WITH_YOUR_SPARKLE_EDDSA_PUBLIC_KEY` placeholder).

## EdDSA update signing (Sparkle)

Sparkle verifies every downloaded update against the public key baked into the
app (`SUPublicEDKey`). After building the `.dmg`, produce its signature:

```bash
./bin/sign_update dist/Bogi-0.1.0.dmg
# → sparkle:edSignature="…" length="…"
```

Copy the `edSignature` and `length` values into the appcast `<enclosure>` (see
`appcast.xml`). If you ever lose the private key you cannot ship updates that
existing installs will accept, so back it up securely.

## Full release pipeline

```text
build → sign → notarize → staple → DMG → (sign DMG) → appcast → publish
```

Concretely, from the repo root:

```bash
# 0) Build a Bogi.app bundle from the SwiftPM target and copy in
#    Resources/Info.plist + Resources/Bogi.entitlements. (Bundle assembly is
#    project-specific; the scripts below take the finished .app as input.)
APP=build/Bogi.app
ID="Developer ID Application: <Your Org> (TEAMID)"

# 1) Sign with the Hardened Runtime + entitlements (signs nested code first).
SIGN_IDENTITY="$ID" scripts/macos/sign.sh "$APP"

# 2) Notarize + staple (credentials read from env / keychain profile).
AC_NOTARY_PROFILE=bogi scripts/macos/notarize.sh "$APP"

# 3) Package a (optionally signed) DMG.
SIGN_IDENTITY="$ID" scripts/macos/package-dmg.sh "$APP" 0.1.0
#    → dist/Bogi-0.1.0.dmg

# 4) Sign the DMG for Sparkle and grab the signature.
./bin/sign_update dist/Bogi-0.1.0.dmg

# 5) Edit apps/macos/Bogi/Distribution/appcast.xml: fill the placeholders
#    (VERSION_SHORT, VERSION_BUILD, PUB_DATE, DOWNLOAD_URL, FILE_SIZE,
#     ED_SIGNATURE). PUB_DATE is `date -R`.

# 6) Publish the .dmg and appcast.xml to the host behind SUFeedURL
#    (https://updates.bogi.app/appcast.xml). Installed apps poll the feed and
#    self-update via Sparkle.
```

### Notes

- **Hardened Runtime is mandatory for notarization.** `sign.sh` always passes
  `--options runtime`.
- **Sandbox is intentionally off.** Bogi reads the Accessibility tree of other
  apps (AXUIElement), which the App Sandbox forbids; the entitlements file omits
  `com.apple.security.app-sandbox`.
- **Notarize the DMG too (optional but recommended).** You can run the same
  `notarytool submit` + `stapler staple` flow on the `.dmg` for the smoothest
  first-download experience; `notarize.sh` targets the `.app`, and stapling the
  DMG can be added analogously.
- **Versioning.** `sparkle:version` (build number) must increase monotonically;
  `sparkle:shortVersionString` is the human-facing marketing version. Keep them
  in sync with `CFBundleVersion` / `CFBundleShortVersionString` in `Info.plist`.

## Files

| File | Purpose |
| --- | --- |
| `appcast.xml` | Sparkle feed template; one `<item>` per release. |
| `../Resources/Info.plist` | `SUFeedURL`, `SUPublicEDKey`, usage strings. |
| `../Resources/Bogi.entitlements` | Hardened-runtime entitlements. |
| `../../../../scripts/macos/sign.sh` | Developer ID signing + hardened runtime. |
| `../../../../scripts/macos/notarize.sh` | Notary submit + staple. |
| `../../../../scripts/macos/package-dmg.sh` | Build the DMG. |
