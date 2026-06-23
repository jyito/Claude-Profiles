## What & why

<!-- One or two sentences on the change and the motivation. -->

## Checklist

- [ ] `bash tests/run-tests.sh` passes
- [ ] `shellcheck -S error src/engine.sh cli/claude-profiles.sh scripts/*.sh` is clean
- [ ] `bash scripts/build.sh` assembles the bundle
- [ ] Docs updated (README / CLAUDE.md / CHANGELOG) if behavior changed
- [ ] **Non-negotiables honored:** no new dependency, no network I/O, no
      credential handling, Claude.app unmodified, every `rm -rf` `${var:?}`-guarded
- [ ] SwiftUI view changes verified via the golden-snapshot harness
      (`swift run ProfilesSnapshotTests`) + maintainer visual/live QA of the
      running window; `badge-icon.applescript` changes osacompile parse-checked
      and verified on a **real Mac** (state which macOS version)
