# Togi.app crash-on-launch — fix + build handoff

> **Audience:** Claude (or a human) running on **Michelle's build machine**, where the
> Developer ID signing identity and notarization credentials live. This document is
> self-contained: it explains the crash, the exact code/layout that must be in place,
> and how to build + verify a working signed/notarized DMG.

---

## 1. Symptom

`Togi.app` (shipped inside `Togi-*.dmg`) crashes **immediately on every launch**, on any
machine other than the one it was compiled on. The DMG itself is fine — valid, signed,
and notarized; Gatekeeper accepts it. This is **not** a "damaged / unidentified
developer" problem. The app process starts, then dies with `SIGTRAP`.

Crash report (`~/Library/Logs/DiagnosticReports/Bogi-*.ips`) shows:

```
Exception: EXC_BREAKPOINT (SIGTRAP)
BogiApp/resource_bundle_accessor.swift:12: Fatal error: could not load resource bundle:
  from   <App>.app/Bogi_BogiApp.bundle
  or     /Users/michellezhang/togi-release/apps/macos/Bogi/.build/.../release/Bogi_BogiApp.bundle

Stack: BogiApp.body → MenuBarExtra.init → BogiAsset.mascot → Bundle.module → fatalError
```

---

## 2. Root cause

The mascot image was loaded through SwiftPM's `Bundle.module` (declared via
`resources: [.copy("Resources/mascot.png")]` in `Package.swift`).

For an `executableTarget` built with `swift build`, the **generated `Bundle.module`
accessor only searches two locations**:

1. `Bundle.main.bundleURL` + `Bogi_BogiApp.bundle` → inside a `.app` this is the **app
   root**: `Bogi.app/Bogi_BogiApp.bundle`
2. a **hardcoded absolute build path** that only exists on the original build machine
   (`/Users/michellezhang/.../.build/.../release/Bogi_BogiApp.bundle`)

It does **NOT** look in `Contents/Resources/` or `Contents/MacOS/`. The packaging script
used to copy the resource bundle into those two directories — so the accessor never found
it and `fatalError`'d at launch. (`BogiAsset.mascot` has an SF-Symbol fallback, but it
never runs: `Bundle.module` traps inside its own initializer, before the fallback.)

You **cannot** fix this by putting the bundle at the `.app` root — that breaks code
signing with `unsealed contents present in the bundle root`.

**Fix:** stop using `Bundle.module`. Load `mascot.png` from `Bundle.main` and stage it
into `Contents/Resources/` — the standard macOS layout.

---

## 3. Required source state (the actual fix)

These three edits must be present in the checkout before building. They are already
applied on branch `claude/peaceful-kare-4a3134`; if Michelle's machine is on a branch
without them, apply them.

### 3a. `Sources/BogiApp/UI/BogiTheme.swift` — load from `Bundle.main`

```swift
enum BogiAsset {
    static let mascot: Image = {
        if let url = Bundle.main.url(forResource: "mascot", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return Image(nsImage: image)
        }
        return Image(systemName: "tortoise.fill")
    }()
}
```

`Bundle.module` → **`Bundle.main`**. This is the only `Bundle.module` use in the codebase
(verify with `grep -rn "Bundle.module" Sources`).

### 3b. `Package.swift` — remove the SPM resource declaration

The `BogiApp` target must **not** declare `mascot.png` as a resource (otherwise SwiftPM
regenerates the broken `Bundle.module` accessor):

```swift
.executableTarget(
    name: "BogiApp",
    dependencies: [
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "MarkdownUI", package: "swift-markdown-ui")
    ]
    // NO `resources:` block here.
),
```

`Sources/BogiApp/Resources/mascot.png` stays on disk — it's just no longer an SPM
resource; the packaging script copies it directly (3c).

### 3c. `Packaging/build-app.sh` — stage the asset into `Contents/Resources`

Replace the old "copy `*.bundle` into MacOS + Resources" loop with a direct copy:

```bash
cp "Sources/BogiApp/Resources/mascot.png" "$APP/Contents/Resources/mascot.png"
```

---

## 4. Exact `.app` layout that must result

After `build-app.sh` assembles `build/Bogi.app`, it MUST look like this:

```
Bogi.app/
├── Contents/
│   ├── Info.plist                     ← from Packaging/Info.plist
│   ├── MacOS/
│   │   └── Bogi                       ← the release binary (Mach-O arm64)
│   └── Resources/
│       ├── mascot.png                 ← loaded via Bundle.main  ✅ THE FIX
│       └── sidecar/
│           ├── main.cjs               ← built Node sidecar
│           ├── node                   ← pinned Node v22.11.0 runtime (arm64)
│           └── node_modules/          ← incl. native .node addons (better-sqlite3 etc.)
```

What must **NOT** be present (these caused / would re-cause the crash):

- ❌ `Bogi.app/Bogi_BogiApp.bundle`  (app root — breaks codesign)
- ❌ `Bogi.app/Contents/MacOS/Bogi_BogiApp.bundle`
- ❌ `Bogi.app/Contents/Resources/Bogi_BogiApp.bundle`
- ❌ any `*.bundle` SwiftPM resource bundle anywhere in the `.app`

The mascot is a **plain file** at `Contents/Resources/mascot.png`, not a nested bundle.

---

## 5. Build, sign, notarize (on Michelle's machine)

`build-app.sh` is gated on a Developer ID + notary profile. Set both, then run it.

```bash
cd apps/macos/Bogi

# Apple Developer ID Application identity (exact string from `security find-identity -v -p codesigning`)
export DEVELOPER_ID="Developer ID Application: Michelle Zhang (96C658N2KK)"

# Notary profile name previously stored via:
#   xcrun notarytool store-credentials <PROFILE_NAME> --apple-id <id> --team-id 96C658N2KK --password <app-specific-pw>
export NOTARY_PROFILE="<your-notary-profile-name>"

Packaging/build-app.sh
```

The script will:
1. `swift build -c release`
2. assemble `build/Bogi.app` with the layout in §4
3. build the Node sidecar (`npm ci && npm run build`) and embed Node v22.11.0
4. codesign the sidecar `node` + every `*.node`, then the outer `.app`
   (hardened runtime + `Bogi.entitlements`)
5. `hdiutil create … build/Bogi.dmg`
6. `notarytool submit --wait` + `stapler staple` the DMG and the `.app`

Output: **`apps/macos/Bogi/build/Bogi.dmg`**.

> If `DEVELOPER_ID` is unset the script still builds an **unsigned** `.app` for local
> testing only (won't pass Gatekeeper on other machines). If `NOTARY_PROFILE` is unset it
> signs but skips notarization (Gatekeeper will block it on download).

---

## 6. Verify the fix BEFORE shipping

Run these after the build. All must pass.

```bash
cd apps/macos/Bogi
APP="build/Bogi.app"

# (a) The broken accessor must be GONE from the binary — expect: 0
strings -a "$APP/Contents/MacOS/Bogi" | grep -c "could not load resource bundle"

# (b) The mascot must be a plain file in Resources — expect: the PNG path
ls "$APP/Contents/Resources/mascot.png"

# (c) No SwiftPM resource bundle must remain anywhere — expect: no output
find "$APP" -name "*.bundle"

# (d) Signature + notarization must be accepted — expect: "accepted ... Notarized Developer ID"
spctl -a -vvv "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# (e) Smoke-test launch from a clean, quarantined location (mimics a real download).
#     Copy out of the DMG, then launch. Bogi is a MENU BAR app (no window) — success =
#     the process is still alive after a few seconds and no new crash report appears.
hdiutil attach "build/Bogi.dmg" -nobrowse
cp -R "/Volumes/Bogi/Bogi.app" /tmp/BogiSmoke.app   # adjust volume name if different
hdiutil detach "/Volumes/Bogi"
open /tmp/BogiSmoke.app
sleep 6
pgrep -lf "/tmp/BogiSmoke.app/Contents/MacOS/Bogi" \
  && echo "RUNNING — fix confirmed" \
  || { echo "CRASHED"; ls -t ~/Library/Logs/DiagnosticReports/Bogi-*.ips | head -1; }
pkill -f "/tmp/BogiSmoke.app/Contents/MacOS/Bogi"; rm -rf /tmp/BogiSmoke.app
```

To read a crash report if (e) fails:
```bash
F=$(ls -t ~/Library/Logs/DiagnosticReports/Bogi-*.ips | head -1)
tail -n +2 "$F" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["procPath"]);print(d.get("exception"));[print(hex(fr.get("imageOffset",0)),fr.get("symbol","")) for t in d["threads"] if t.get("triggered") for fr in t["frames"][:14]]'
```

---

## 7. Notes / follow-ups

- **General rule for this app:** any future bundled asset (icons, sounds, etc.) should be
  copied into `Contents/Resources/` by `build-app.sh` and loaded via `Bundle.main` —
  **never** via `Bundle.module` / SwiftPM `resources:`, because the `swift build`
  executable accessor is incompatible with a signed `.app`.
- **Cosmetic, unrelated to the crash:** the binary / bundle id (`sh.bogi.app`) / DMG
  volume are all "Bogi", while the user-facing `CFBundleName` is "Togi" and the artifact
  is `Togi-*.dmg`. Worth reconciling the "Bogi" vs "Togi" branding at some point.
- An older, *separate* crash (`EXC_CRASH`/`SIGABRT` in `dyld4::prepare` at launch) appeared
  in some pre-this-build `.ips` files — that was a dyld/link issue in an earlier build and
  is not this bug. The current build links and runs cleanly.
