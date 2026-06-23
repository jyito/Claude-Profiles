# Maintaining Claude Profiles

Operational runbook for the maintainer. The CI/CD design rationale lives in
[`docs/superpowers/specs/2026-06-14-devsecops-cicd-design.md`](superpowers/specs/2026-06-14-devsecops-cicd-design.md);
this file is the checklist of things the workflows **can't** configure for
themselves because they live in repository settings or require a human.

## CI/CD at a glance

| Workflow | File | Trigger | What it does |
|----------|------|---------|--------------|
| CI | `.github/workflows/ci.yml` | push, PR | shellcheck + actionlint, test suite, gitleaks scan, build |
| macOS CI | `.github/workflows/ci-macos.yml` | PR to `main`, weekly, called by Release | `swift build` + Layer-1 logic + Layer-2 snapshot render + bash suite + icon + bundle build + `badge-icon` osacompile parse-check, on real macOS |
| Scorecard | `.github/workflows/scorecard.yml` | push to `main`, weekly | OpenSSF supply-chain score (public repos only) |
| Release | `.github/workflows/release.yml` | tag `v*` | gate on macOS CI, build, optional sign+notarize, SLSA provenance, publish |
| Dependabot | `.github/dependabot.yml` | weekly | bump pinned action SHAs (grouped) |

All third-party actions are **pinned to a full commit SHA** with the version in
a trailing comment. Dependabot updates the SHA and the comment together; review
its PRs like any other code change. Never replace a SHA pin with a tag — that
re-opens the supply-chain hole the pinning closes.

## One-time repository settings (GitHub UI)

These are not in version control. Set them once when the repo is created, and
re-confirm after going public.

### Branch protection — `main`
Settings → Branches → Add rule, branch name `main`:
- [x] Require a pull request before merging (1 approval; CODEOWNERS routes to you)
- [x] Require status checks to pass: `lint (shellcheck + actionlint)`,
      `test suite (linux, shimmed)`, `build assembles`, `secret scan (gitleaks)`
- [x] Require branches to be up to date before merging
- [x] Require conversation resolution before merging
- [x] Do not allow bypassing the above (applies the rule to admins too)

### Secret scanning + push protection
Settings → Code security and analysis:
- [x] Secret scanning — **on** (free on public repos)
- [x] Push protection — **on** (blocks commits that contain a known secret
      pattern before they land; complements the gitleaks history scan in CI)
- [x] Dependabot alerts + security updates — **on**
- [x] Private vulnerability reporting — **on** (the intake path named in
      [`SECURITY.md`](../SECURITY.md))

### GitHub Pages (marketing site)
Settings → Pages → Source: **Deploy from a branch**, branch `main`, folder
`/docs`. The landing page is [`docs/index.html`](index.html). Pages is only
available on public repos (or with a paid plan) — flip it when the repo goes
public.

## Release process

Releases are tag-driven. From a clean `main`:

1. Move the `## [Unreleased]` section in [`CHANGELOG.md`](../CHANGELOG.md) under
   a new `## [x.y.z] — YYYY-MM-DD` heading. The Release workflow extracts that
   exact section for the GitHub Release notes (falls back to auto-generated
   notes if the heading is missing).
2. `git tag vX.Y.Z && git push origin vX.Y.Z`
3. The Release workflow runs the macOS CI matrix, builds the DMG + zip, signs +
   notarizes **if** the signing secrets are present (see below), attaches SLSA
   build provenance (public repos only), and publishes the GitHub Release with
   the two artifacts attached.

Unsigned artifacts still ship — they just carry a Gatekeeper quarantine prompt
on download (right-click → Open). Signing removes that friction.

> **First public release — verify the gated steps.** While the repo is private,
> the `attest build provenance` step (Release) and the whole Scorecard workflow
> (incl. `upload-artifact`) are gated off and never run, so CI can't exercise
> them. Dependabot may bump these actions across major versions unverified
> (e.g. `attest-build-provenance` v2→v4, `upload-artifact` v4→v7). On the first
> public release, watch those two steps specifically and pin back a major if one
> breaks.

### Signing secrets (optional)
The sign+notarize step is gated on `SIGN_IDENTITY` being set and is skipped
cleanly when it is absent, so the pipeline works before you have a Developer ID.
To enable signing, add these repository secrets (Settings → Secrets and
variables → Actions):

| Secret | What it is |
|--------|------------|
| `SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_DEVELOPER_ID_P12_BASE64` | `base64 -i cert.p12` of the exported Developer ID cert + key |
| `P12_PASSWORD` | password set when exporting the `.p12` |
| `APPLE_ID` | Apple ID email for notarization |
| `APPLE_TEAM_ID` | 10-char team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | app-specific password (appleid.apple.com), **not** your Apple ID password |

The workflow imports the cert into a throwaway keychain in `RUNNER_TEMP` and
deletes it after signing; nothing persists on the runner.

## Cost note
macOS runner minutes bill at 10× on **private** repos. While private, keep the
macOS matrix small (it's already pinned to a single `macos-latest` for PRs and
only fans out to the version matrix on schedule/release). Once public, GitHub
Actions minutes are free for public repositories.

## Local pre-flight (before any push)
```bash
bash tests/run-tests.sh                       # bash/engine suite (Linux or macOS)
shellcheck -S error src/engine.sh cli/claude-profiles.sh scripts/*.sh
cd app && swift build && swift run ProfilesCoreTests && swift run ProfilesSnapshotTests && cd ..
bash scripts/build.sh                          # compile + assemble the bundle
```
Linux CI runs the bash suite + shellcheck + actionlint + gitleaks + build; the
macOS CI job adds `swift build`, both Swift runners, the icon regen, and the
`badge-icon.applescript` osacompile parse-check. The running SwiftUI window and
`src/badge-icon.applescript`'s rendered output are the layers CI can't fully
exercise — verify those on a real Mac and note the macOS version in the PR.
