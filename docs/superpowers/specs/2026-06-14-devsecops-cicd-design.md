# DevSecOps CI/CD for Claude Profiles — design

**Status:** approved design (2026-06-14)
**Goal:** comprehensive, **free** (GitHub Actions only, no paid services)
Dev/Sec/Ops pipeline tailored to a zero-dependency macOS bash + AppleScript app,
and fix the currently-broken CI along the way (done — `41f6334`, SC1087 brace).

## Decisions (from brainstorming)

1. **Scope: high-signal, tailored.** Comprehensive but curated to what actually
   has signal for a zero-dependency bash/AppleScript project. Skip scanners that
   only add noise/red-X's here (see "Deliberately skipped").
2. **CD: signing-ready release pipeline.** Tag-triggered build + GitHub Release
   with artifacts; optional codesign/notarize that auto-activates when the Apple
   cert + credentials are added as repo secrets (unsigned until then — the repo
   has 0 Developer ID certs today).
3. **macOS testing: smart-limited now, broad when public.** Linux on every
   push/PR (cheap); macOS on PRs→main + a weekly cron + release (conserves
   private-repo minutes, where macOS bills 10×); a version matrix only on
   cron/release. One-line change to run macOS on every push once the repo is
   public (Actions are then free/unlimited).

## Constraints (carried from CLAUDE.md)

- **Zero runtime dependencies** in the app; CI may install lint tools.
- **Never touch credentials.** No secrets except the user's own signing creds
  (added later by the maintainer), used only by `release.yml`.
- The test suite runs on Linux via shimmed macOS tools; macOS runners exercise
  the real applet/osacompile/sips layer the suite can't.

## Architecture — five pieces

### `.github/workflows/ci.yml` (rework existing)
Triggers: `push` to `main`, all `pull_request`. Top-level `permissions: contents: read`.
Jobs (ubuntu-latest, each begins with a `harden-runner` audit step):
- **lint** — install shellcheck; `shellcheck -S error src/launcher src/engine.sh
  cli/claude-profiles.sh scripts/*.sh`; **actionlint** on `.github/workflows/*.yml`.
- **test** — `bash tests/run-tests.sh`.
- **build** — `bash scripts/build.sh && test -f "dist/Claude-Profiles.zip"`.

### `.github/workflows/ci-macos.yml` (new)
Triggers: `pull_request` to `main`, `schedule` (weekly, e.g. Mon 06:00 UTC),
`workflow_call` (so `release.yml` can reuse it). `permissions: contents: read`.
- **macos** job, `runs-on: ${{ matrix.os }}`. Matrix: `[macos-latest]` for PRs;
  `[macos-13, macos-14, macos-15]` for `schedule`/`workflow_call` (select via a
  matrix expression keyed on `github.event_name`).
- Steps: harden-runner audit · checkout · `bash tests/run-tests.sh` ·
  `bash scripts/make-icon.sh` (sips SVG→iconset path) · `bash scripts/build.sh` ·
  `osacompile`-parse both applescripts (substitute `__RESOURCES__` with a temp
  path, compile, assert exit 0 — mirrors the local compile-check used in dev).

### `.github/workflows/release.yml` (new)
Trigger: `push` tags matching `v*`. `permissions: contents: write` (to publish).
- **gate**: `uses: ./.github/workflows/ci-macos.yml` (release blocks on macOS tests).
- **release** job (macos-latest): harden-runner · checkout · `make-icon` ·
  `build.sh` · **optional sign**: a step `if: ${{ secrets.SIGN_IDENTITY != '' }}`
  that imports the Developer-ID cert from secrets into a temp keychain and runs
  `scripts/sign.sh` (stays skipped/unsigned until secrets exist) ·
  extract the tag's section from `CHANGELOG.md` as the release body ·
  publish a GitHub Release with `dist/Claude-Profiles.dmg` + `dist/Claude-Profiles.zip`
  using `gh release create` (or a SHA-pinned `softprops/action-gh-release`).
- **Secrets the maintainer adds later** (documented, not stored now):
  `SIGN_IDENTITY`, `APPLE_DEVELOPER_ID_P12_BASE64`, `P12_PASSWORD`,
  `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`. The sign step
  base64-decodes the p12, `security create-keychain`/`import`/`set-key-partition-list`
  into a temp keychain, creates a `notarytool` profile, runs `sign.sh`, then
  deletes the temp keychain.

### `.github/workflows/scorecard.yml` (new)
Triggers: `schedule` (weekly), `push` to `main`. `permissions: security-events: write,
contents: read, id-token: write`. Runs `ossf/scorecard-action` (SHA-pinned),
uploads SARIF to code scanning, publishes a Scorecard badge. (Requires the repo
public for full results.)

### `.github/dependabot.yml` (new config)
`package-ecosystem: github-actions`, `directory: /`, weekly schedule. Opens PRs to
bump pinned action SHAs — the permanent fix for action deprecations (no more
manual `checkout@v4`→`v5` chases).

## Security / supply-chain details

- **Pin all third-party actions to full commit SHAs**, each with a trailing
  `# vX.Y.Z` comment. Dependabot keeps them current.
- **Least-privilege tokens**: `contents: read` default; elevate per-workflow only
  where required (release write, scorecard security-events).
- **harden-runner** (`step-security/harden-runner`, `egress-policy: audit`) as the
  first step of every job — non-blocking egress monitoring.
- **gitleaks** secret scan on push/PR (its own small job in `ci.yml` or a
  `security.yml`; keep it in `ci.yml` to limit file count).
- **GitHub-native, enabled in repo settings (documented checklist):** Secret
  Scanning, Push Protection, Dependabot alerts/security updates.

## Deliberately skipped (documented so it's a choice, not an oversight)

- **CodeQL** — no shell support; the small inline JS in `dashboard.html` has no
  dependencies and no server surface. Low signal, real maintenance/noise.
- **Dependency / SBOM / container scanning (Trivy, Grype, etc.)** — the project
  has zero dependencies and ships no container. Nothing to scan.
- **shfmt** — would reformat the maintainer's deliberately hand-tuned script
  style; shellcheck already covers correctness.

## Ops / repo settings (maintainer checklist — settings, not files)

- **Branch protection** on `main`: require the `ci.yml` checks to pass and a PR
  before merge.
- Enable the native security features listed above.
- **GitHub Pages**: serve from `main` `/docs` (static landing page; no deploy
  workflow needed).
- **README badges**: CI status + OpenSSF Scorecard.

## Testing / verification

- **actionlint** in CI lints the workflow YAML (catches the SC1087-class of typo
  in Actions form).
- Workflows can't be run locally without Docker/act; verification is: author with
  actionlint clean, push to a short-lived branch, watch the runs with
  `gh run watch`, iterate. The release flow is validated by pushing a throwaway
  pre-release tag (e.g. `v0.0.0-test`) and deleting the resulting release/tag.

## Rollout order (for the implementation plan)

1. `dependabot.yml` + pin existing `ci.yml`'s actions to SHAs (low-risk, immediate
   supply-chain win, fixes the deprecation source).
2. Rework `ci.yml`: split lint/test/build jobs, add actionlint + harden-runner +
   least-privilege permissions + gitleaks.
3. `ci-macos.yml` (smart-limited triggers + matrix).
4. `scorecard.yml`.
5. `release.yml` (signing-ready, currently-unsigned path).
6. README badges + a `docs/CI.md` (or a CLAUDE.md section) documenting the repo
   settings the maintainer must toggle and the release-signing secrets.
7. Validate via a throwaway branch + a throwaway pre-release tag; clean up.
