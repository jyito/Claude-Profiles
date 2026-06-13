# Spike: can a profile show its own name (not "Claude") while running?

**Date:** 2026-06-13 · **Verdict: No (not worth it). Keep the Dock badge.**

## The question

Running profiles all launch the real, unmodified `Claude.app`, so macOS
identifies every one of them as **"Claude"** in the menu bar, ⌘-Tab, and the
running Dock icon. The per-profile badge distinguishes the *launcher* icons
(Spotlight, Launchpad, pinned launchers) but **not** the running instances.
Could a per-profile app present its own name (`Claude Business`) while still
running Claude's code?

## What was tried (empirically, on real macOS)

`Claude.app` is **706 MB**, **hardened-runtime**, **Developer ID** (Anthropic,
team `Q6L2SF6YDW`). The executable itself is tiny (119 KB) — the weight is in
`Contents/Frameworks` + `Contents/Resources`.

**Overlay bundle** (the lightweight idea): a 132 KB bundle with its own
`Info.plist` (name/icon/id), a copy of Claude's 119 KB binary, and **symlinks**
to Claude's `Frameworks`/`Resources`/`Helpers`.

| Step | Result |
|------|--------|
| Build + launch as-is | **Rejected** — `Launchd job spawn failed`, POSIX **163**. Changing `Info.plist` breaks the bundle code-signature seal; hardened runtime refuses to spawn. |
| Shallow ad-hoc re-sign (`codesign --force --sign -`, no `--deep` so it can't touch Claude via the symlinks) | Signature now valid (ad-hoc, no team, runtime flag dropped). `open` returns 0… |
| Launch the re-signed overlay | **Crashes instantly** — `EXC_BREAKPOINT` / SIGTRAP, data dir never written. Claude's Electron build has **integrity validation** (asar-integrity fuse / code-signing self-check) that detects the re-signed/foreign bundle and deliberately aborts. |

Claude.app was **never modified** throughout (verified: `codesign -v` still
passes; Frameworks mtime unchanged). Only symlinks pointed at it.

## Why even the heavy path isn't worth it

A full **706 MB copy** with an ad-hoc re-sign is the only remaining theoretical
path (real Resources → the asar-integrity hash would match). But:

- **706 MB per profile.** Five profiles = 3.5 GB of duplicated app.
- **Breaks auto-update.** Copies diverge from the real app; every Claude
  release would need a re-copy + re-sign. Our whole architecture exists to
  *avoid* this (share one install, updates just work).
- **Security downgrade.** Ad-hoc re-signing strips Anthropic's Developer ID
  signature from a copy of their app — questionable to ship.
- **May still trip** the code-signing self-check (the SIGTRAP above could be
  the signature check, not only asar integrity).

## Decision

**Do not pursue branded per-profile apps.** Running instances stay identified
as "Claude" — a deliberate, honest trade-off of the zero-modification
architecture (no signature break, no 706 MB copies, auto-updates keep working).
The **per-profile Dock badge** (shipped) plus distinct launcher names are the
trademark-safe, signature-safe way to tell profiles apart. To raise a specific
instance, use **Show Window** (targets the instance by PID).

If Anthropic ever ships official multi-account support, this all goes away.
Until then, badges are the answer. Don't re-spike this without new information
(e.g. Electron fuses changing, or an official per-instance naming hook).
