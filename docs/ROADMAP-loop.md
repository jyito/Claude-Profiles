# Roadmap — autonomous build loop

Progress tracker for the self-paced `/loop` build. One feature per branch/PR.

| # | Item | Status |
|---|------|--------|
| 0 | Merge PR #4 (the /dev/ptmx leak feature) + delete branch | ✅ merged to main (9cab6a2) |
| 1 | Auto-restart on leak threshold (opt-in Settings, enforced in `autotick`) | ✅ PR #5 (green) |
| 2 | Menu-bar switcher (status-bar item: focus/launch profiles) | ✅ PR #6 — ⚠ needs real-Mac verify |
| 3 | Hotkeys — in-app ⌘⌥1..9 + headless `focus` + Hammerspoon recipe | ✅ PR open |
| 4 | Remote polish — live `screen` session status on card + QR of the SSH line | 🔨 next |
| 5 | README glow-up + hero image | ⛔ FLAG: needs a screenshot from maintainer |
| 6 | Distribution prep — Homebrew cask + tighten sign.sh/docs | ⛔ FLAG: signing/notarization blocked on Apple Developer account |

## Notes
- Non-negotiables hold throughout: zero deps, zero network, macOS built-ins only,
  bash 3.2, never touch credentials / Claude.app / the default data dir.
- True global hotkeys can't be done in pure AppleScriptObjC (no Carbon callbacks /
  NSEvent blocks). Item 3 ships in-app ⌘⌥1..9 (window focused) + a headless
  `engine focus` + an optional Hammerspoon recipe for the global chord — app stays
  zero-dep.
- Item 2 (menu-bar) native behavior needs maintainer verification on a real Mac.
- Items 5–6 require maintainer action (screenshot, Apple account).
- PRs branch off `main` and aren't auto-merged; expect trivial merge-order
  conflicts in shared append-points (engine dispatch, test suite, docs lists).
