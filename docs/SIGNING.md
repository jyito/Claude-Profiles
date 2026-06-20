# Signing, notarization & Homebrew (maintainer guide)

> **Status: BLOCKED on an Apple Developer account.** Everything below is the
> ready-to-run procedure; it needs a paid **Apple Developer Program** membership
> ($99/yr) for the Developer ID certificate. Until then, releases ship **unsigned**
> and downloaders clear Gatekeeper once via System Settings → Privacy & Security →
> **Open Anyway** (see [INSTALL.md](INSTALL.md)). Locally built bundles are never
> quarantined, so this affects *downloaders only*.

Why bother: a signed + notarized DMG opens with a normal double-click for everyone,
and it's a prerequisite for a clean Homebrew cask.

## One-time setup

1. **Join the Apple Developer Program** and, in your Apple account, create a
   **Developer ID Application** certificate. Install it in your login keychain.
   Confirm it's there:
   ```sh
   security find-identity -v -p codesigning
   # → "Developer ID Application: Your Name (TEAMID)"
   ```
2. **Store a notarytool credential profile** once (uses an app-specific password or
   an App Store Connect API key — never your raw Apple ID password in scripts):
   ```sh
   xcrun notarytool store-credentials notary \
     --apple-id you@example.com --team-id TEAMID
   ```
   > Do this yourself in a terminal — the Claude Profiles tooling never handles
   > your Apple credentials.

## Release via CI (recommended)

`.github/workflows/release.yml` signs + notarizes automatically on a version-tag
push — no local signing needed. One-time, add these **GitHub repo secrets**
(Settings → Secrets and variables → Actions). Set them yourself; they never pass
through this tooling:

| Secret | What |
|--------|------|
| `SIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` (gates the sign step) |
| `APPLE_DEVELOPER_ID_P12_BASE64` | your Developer ID cert exported as `.p12`, base64'd: `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | the password you set when exporting the `.p12` |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | your 10-char Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | an app-specific password (appleid.apple.com → Sign-In and Security) |

Export the `.p12` from **Keychain Access** → your *Developer ID Application* key →
right-click → Export, set a password (that's `P12_PASSWORD`).

Then cut a release:
```sh
# version already bumped in src/Info.plist + a matching ## [x.y.z] CHANGELOG section
git tag v0.6.0 && git push origin v0.6.0
```
The workflow runs the macOS test matrix, builds, imports the cert into a throwaway
keychain, runs `scripts/sign.sh` (sign → notarize → staple), extracts release notes
from the CHANGELOG's `[x.y.z]` section, appends `SHA256SUMS.txt`, attaches SLSA build
provenance, and publishes the GitHub Release with the signed DMG/zip. (The sign step
is skipped automatically if `SIGN_IDENTITY` isn't set, so unsigned releases still work.)

## Manual / local signing (alternative)

```sh
bash scripts/build.sh                       # assemble dist/Claude Profiles.app (+ DMG)
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE=notary \
  bash scripts/sign.sh                       # sign → notarize → staple app + DMG + zip
```

`scripts/sign.sh` already does the full sequence: hardened-runtime codesign,
strict verify, repack the zip/DMG, `notarytool submit --wait`, `stapler staple`,
and a final `spctl` assessment. With `SIGN_IDENTITY` but no `NOTARY_PROFILE` it
signs without notarizing (still blocked for downloaders — notarize for real
releases).

Verify the result opens clean:
```sh
spctl -a -vvv -t install "dist/Claude-Profiles.dmg"   # → accepted, source=Notarized Developer ID
xcrun stapler validate "dist/Claude Profiles.app"
```

Then attach the signed `Claude-Profiles.dmg` / `.zip` to the GitHub release as
usual; the existing release workflow publishes `SHA256SUMS.txt` alongside them.

## Homebrew cask

A ready-to-publish cask lives at
[`packaging/homebrew/claude-profiles.rb`](../packaging/homebrew/claude-profiles.rb).
It can't go live until releases are **signed + notarized** — Homebrew (and macOS)
will block an unsigned cask app for downloaders.

When signing is in place, per release:

1. Compute the DMG hash and drop it into the cask's `sha256`:
   ```sh
   shasum -a 256 "dist/Claude-Profiles.dmg"
   ```
2. Bump `version` to match the release tag.
3. Publish via a tap repo (the homebrew-core cask process is stricter; a personal
   tap is the easy path):
   ```sh
   # one-time: create github.com/jyito/homebrew-tap with a Casks/ dir
   cp packaging/homebrew/claude-profiles.rb <tap>/Casks/claude-profiles.rb
   # users then:
   brew install --cask jyito/tap/claude-profiles
   ```

Keep the cask's `version`/`sha256` in lockstep with each signed release.
