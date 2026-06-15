## What & why

<!-- One or two sentences on the change and the motivation. -->

## Checklist

- [ ] `bash tests/run-tests.sh` passes
- [ ] `shellcheck -S error src/launcher src/engine.sh cli/claude-profiles.sh scripts/*.sh` is clean
- [ ] `bash scripts/build.sh` assembles the bundle
- [ ] Docs updated (README / CLAUDE.md / CHANGELOG) if behavior changed
- [ ] **Non-negotiables honored:** no new dependency, no network I/O, no
      credential handling, Claude.app unmodified, every `rm -rf` `${var:?}`-guarded
- [ ] AppleScript / applet changes were verified on a **real Mac** (state which
      macOS version), since CI's Linux job can't exercise that layer
