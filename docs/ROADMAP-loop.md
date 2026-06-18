# Roadmap — autonomous build loop

Progress tracker for the self-paced `/loop` build. One feature per branch/PR.

| # | Item | Status |
|---|------|--------|
| 0 | Merge PR #4 (the /dev/ptmx leak feature) + delete branch | ✅ merged to main (9cab6a2) |
| 1 | Auto-restart on leak threshold (opt-in Settings, enforced in `autotick`) | ✅ PR #5 (green) |
| 2 | Menu-bar switcher (status-bar item: focus/launch profiles) | ✅ PR open — ⚠ needs real-Mac verify |
| 3 | Global hotkeys ⌘⌥1..9 → focus a profile's windows | 🔨 next |
| 4 | Remote polish — live `screen` session status on card + QR of the SSH line | ⬜ todo |
| 5 | README glow-up + hero image | ⛔ FLAG: needs a screenshot from maintainer |
| 6 | Distribution prep — Homebrew cask + tighten sign.sh/docs | ⛔ FLAG: signing/notarization blocked on Apple Developer account |

## Notes
- Non-negotiables hold throughout: zero deps, zero network, macOS built-ins only,
  bash 3.2, never touch credentials / Claude.app / the default data dir.
- Items 2–3 are native AppleScriptObjC: built + osacompile-checked + unit-tested
  where possible, but the live AppKit behavior (status item, menu clicks, hotkeys)
  needs the maintainer to verify on a real Mac before merge.
- Items 5–6 require maintainer action (screenshot, Apple account).
