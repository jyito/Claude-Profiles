# Roadmap — autonomous build loop

Progress tracker for the self-paced `/loop` build. One feature per branch/PR.

| # | Item | Status |
|---|------|--------|
| 0 | `/dev/ptmx` leak detection | ✅ merged to main (9cab6a2) |
| 1 | Auto-restart on leak threshold | ✅ PR #5 (green) |
| 2 | Menu-bar switcher | ✅ PR #6 — ⚠ needs real-Mac verify |
| 3 | Hotkeys — in-app ⌘⌥1..9 + headless `focus` + Hammerspoon recipe | ✅ PR #7 (green) |
| 4a | Remote polish — live Claude Code `screen` session status on cards | ✅ PR #8 (green) |
| 4b | Remote polish — QR of the SSH attach line (inline pure-JS encoder) | ✅ PR open — ⚠ phone-scan to confirm |
| 5 | README glow-up + hero image | ⛔ FLAG: needs a screenshot from maintainer |
| 6 | Distribution prep — Homebrew cask + tighten sign.sh/docs | ⛔ FLAG: signing/notarization blocked on Apple Developer account |

## Notes
- Non-negotiables hold throughout: zero deps, zero network, macOS built-ins only,
  bash 3.2, never touch credentials / Claude.app / the default data dir.
- 4b QR: a ~120-line inline byte-mode encoder (v1–5, ECC L). Validated by a
  round-trip test + the spec format-BCH table; a real phone scan is the final
  check (a v3 render was eyeballed — structurally valid).
- Item 2 (menu-bar) native behavior needs maintainer verification on a real Mac.
- Items 5–6 require maintainer action (screenshot, Apple account).
- PRs branch off `main`, not auto-merged. Suggested merge order: 5 → 7 → 4a → 4b → 6 → 2.
