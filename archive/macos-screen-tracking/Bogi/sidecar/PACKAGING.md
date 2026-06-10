# Sidecar packaging findings (spike B0)

- Node runtime: v22.11.0 darwin-arm64 (pinned).
- Embedded at: `Bogi.app/Contents/Resources/sidecar/node`.
- Sign: `codesign --force --options runtime --timestamp --sign "<Developer ID>" <node>`.
- Entitlements required: com.apple.security.cs.allow-jit (+ existing disable-library-validation).
- Launch: Process with executableURL = bundled node, arguments = [bundled main.cjs].
- Notarization: the embedded node is stapled as part of the .app submission.
