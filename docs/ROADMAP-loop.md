# Roadmap — autonomous build loop

Progress tracker for the self-paced `/loop` build. One feature per branch/PR.

| # | Item | Status |
|---|------|--------|
| 0 | Merge PR #4 (the /dev/ptmx leak feature) + delete branch | ✅ merged to main (9cab6a2) |
| 1 | Auto-restart on leak threshold (opt-in Settings, enforced in `autotick`) | ✅ PR #5 (green) |
| 2 | Menu-bar switcher (status-bar item: focus/launch profiles) | ✅ PR #6 — ⚠ needs real-Mac verify |
| 3 | Hotkeys — in-app ⌘⌥1..9 + headless `focus` + Hammerspoon recipe | ✅ PR #7 (green) |
| 4a | Remote polish — live Claude Code `screen` session status on cards | ✅ PR open |
| 4b | Remote polish — QR of the SSH line in the Remote modal | ⏸ DEFERRED — recommend skip (see spec); needs maintainer call |
| 5 | README glow-up + hero image | ⛔ FLAG: needs a screenshot from maintainer |
| 6 | Distribution prep — Homebrew cask + tighten sign.sh/docs | ⛔ FLAG: signing/notarization blocked on Apple Developer account |

## Notes
- Non-negotiables hold throughout: zero deps, zero network, macOS built-ins only,
  bash 3.2, never touch credentials / Claude.app / the default data dir.
- 4b (QR): a from-scratch pure-JS QR encoder (~300 lines, Reed-Solomon) can't be
  scannability-verified in CI and adds marginal value over the existing Copy button.
  Recommended skip; awaiting maintainer decision.
- Item 2 (menu-bar) native behavior needs maintainer verification on a real Mac.
- Items 5–6 require maintainer action (screenshot, Apple account).
- PRs branch off `main`, not auto-merged; expect trivial merge-order conflicts in
  shared append-points. Suggested merge order: 5 → 7 → 4a → 6 → 2.
