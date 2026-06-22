# SwiftUI dashboard — Phase 0: de-risking spike (design)

## Why this exists

We're committing to rewrite the dashboard window host from AppleScriptObjC +
WKWebView to a native **SwiftUI** app (full replacement; bash engine + profile
wrappers stay). That's a large rewrite, so **before** designing the full app we
run a **spike**: a small, time-boxed, **throwaway** experiment whose only purpose
is to answer "does SwiftUI + `engine.sh` work cleanly under our real distribution
config?" The output is a go/no-go decision and a list of gotchas — not product
code. The spike code is discarded.

## The one architectural commitment being validated

**The SwiftUI app shells out to the existing `engine.sh`** (bundled in the app's
`Resources/`) via `Process`, consuming the same JSON it emits today. The engine
stays the single source of truth; stats/actions are **not** reimplemented in
Swift. This replaces the `document.title` JS↔native bridge with direct `Process`
calls + `Codable` decoding.

- The app is **non-sandboxed** (Developer ID direct distribution — we already
  chose this over the Mac App Store, which would forbid the spawning/`lsof`/`ps`
  the engine relies on).
- Minimum macOS **14 (Sonoma)** — unchanged; `MenuBarExtra` and the SwiftUI APIs
  we need are available.

*Rejected alternative:* port the engine to Swift — discards a proven, tested,
CLI-shared backend for no benefit and breaks the zero-dependency-engine ethos.

## What the spike builds

A minimal SwiftUI app in a **disposable Xcode project** built in a **gitignored
scratch dir** (e.g. `spike/` added to `.gitignore`, or outside the repo) — **not**
wired into `scripts/build.sh` or CI, and **not committed**. It is **code-signed
with the Developer ID + hardened runtime** so we exercise the real shipping config:

- A window showing one card per profile with **live CPU / memory** read from
  `engine.sh stats`.
- A per-card **Show Window** button (focus by PID).
- One mutating action button (e.g. **Restart** or **Open**).
- A **`MenuBarExtra`** listing the profiles.

## Success criteria (go/no-go gate)

The spike passes only if **all five** hold on the maintainer's Mac:

| # | Unknown | Pass means |
|---|---------|-----------|
| 1 | Process spawn under hardened runtime | The signed, hardened app runs `engine.sh stats` and receives valid JSON (no spawn/exec denial). |
| 2 | Live data loop | A 2s poll runs off the main thread, `Codable`-decodes the stats JSON, updates an `@Observable` model, and the cards refresh smoothly with no main-thread stalls. |
| 3 | Native menu-bar switcher | A `MenuBarExtra` renders and lists the profiles. |
| 4 | Spaces-aware focus | Show Window raises a specific instance by PID via `NSRunningApplication` + the System Events frontmost fallback, including the one-time Automation prompt, across Spaces. |
| 5 | Action round-trip | A button invokes `engine.sh <verb> <slug>` and the UI reflects the result on the next tick. |

**Pass → green-light the full-parity SwiftUI design (a separate spec).**
**Fail on any → stop and reassess** that specific unknown (e.g. hardened-runtime
entitlements, an alternative to `MenuBarExtra`) before designing further.

## Explicitly out of scope (this is the spike, not the app)

No feature parity. **Not** in the spike: the leaked-handle stat / banner / restart
flow, the terminals drill-down, settings, the Remote modal + QR, the badge picker,
keyboard hotkeys, sparklines, cleanup, the new-profile flow, or any polish. Those
belong to the full app and will be specced after the spike passes.

## Deliverable (what is kept)

The spike app itself is discarded. What we commit/keep:

1. A short **findings note** (committed to the repo, e.g. under `docs/`): each of
   the 5 criteria marked pass/fail, plus any entitlements/quirks discovered (so the
   full design starts from validated ground).
2. A **go/no-go** recommendation for the full SwiftUI rewrite.
