# Contributing

Thanks for helping! Ground rules and workflow:

## Principles (non-negotiable)
1. **Never touch credentials.** No code may read, store, transmit, or proxy
   passwords, tokens, cookies, or Keychain items. The per-profile data dir is
   Claude Desktop's own credential store; we only point at it.
2. **No network I/O.** This tool makes zero network connections. PRs adding
   any will be declined.
3. **No dependencies.** macOS built-ins only (bash, osascript, ps, lsof,
   defaults, du). No Homebrew, no Node/Python at runtime.
4. **Never modify Claude.app** — it breaks the code signature.
5. **Data dirs are precious.** Any destructive path needs explicit, typed
   confirmation and `${var:?}` guards on `rm -rf`.

## Workflow
- Run `bash tests/run-tests.sh` before pushing — it runs on Linux or macOS
  (macOS tools are shimmed), so CI mirrors your local run.
- Run `shellcheck src/engine.sh cli/claude-profiles.sh`.
  Annotate intentional violations (e.g. PID word-splitting for `kill`).
- SwiftUI view changes are covered by the golden-snapshot harness
  (`swift run ProfilesSnapshotTests`) plus maintainer visual/live QA of the
  running window. The only AppleScript left is `src/badge-icon.applescript`
  (the icon compositor); changes there must be osacompile parse-checked /
  rendered on real macOS, and the PR should state which macOS version(s).
- Keep dialog copy in sentence case, button labels in Title Case (HIG).
- New engine features need a test in `tests/run-tests.sh`.

## Releases
`scripts/build.sh` assembles `dist/`. On macOS it also builds the DMG via
`scripts/make-dmg.sh`. Signing/notarization is on the roadmap; until then,
release notes must mention the right-click → Open first launch.
