# SwiftUI dashboard — automated testing strategy

Verified, dependency-light testing for the native SwiftUI dashboard, built to work
**without full Xcode** (Command Line Tools only — same constraint the build runs
under). Every tooling choice below was empirically checked in the research pass;
where a layer hits a hard wall (e2e in hosted CI), this says so plainly.

## The shape: a pyramid on top of the existing bash suite

| Layer | What it owns | Tooling | Where it runs | Gates? |
|------|--------------|---------|---------------|--------|
| **0 — bash (exists)** | `engine.sh` JSON **contract** (producer side): every verb runs, emits valid JSON, every field correct | the 124-test `tests/run-tests.sh` + a new per-verb test for any field the app consumes | ubuntu (free) | ✅ every PR |
| **1 — logic (Swift)** | **consumer** side: JSON decode, the ptmx **hysteresis** state machine, byte/percent formatting, alive-first sort, store reaction to good/bad ticks | the spike's proven executable-runner — vendored ~150-line XCTest shim + `swift run ProfilesCoreTests` | macOS-headless | ✅ every PR |
| **2 — visual snapshot** | **visual regression** of deterministic leaf views (card states, sparkline, badges, sheet bodies, KPI strip) | `ImageRenderer` → `NSBitmapImageRep` → golden PNG; `swift run ProfilesSnapshotTests`; `pngdiff.py` (python3 stdlib) | macOS-headless | ✅ every PR |
| **3 — e2e** | **real-scene** behavior nothing else reaches: launch-to-first-render, sheet→wrapper-created, MenuBarExtra populates, Show Window jump | hand-rolled **AXUIElement** driver addressing controls by `accessibilityIdentifier`; stubbed `engine.sh`; assert **engine side-effects**, not pixels | self-hosted/maintainer Mac (**not** hosted CI) | ⚠️ pre-merge gate |

Rough volume: ~120+ logic tests · ~15–30 snapshots · ~5–10 e2e flows, on top of
the 124+ bash tests. A **shared fixture** (a captured real `engine.sh stats`) ties
Layer 0 and Layer 1 together, so a bash field rename surfaces as a Swift decode
failure instead of silent drift.

## Verified facts (the load-bearing ones)

- **`swift test`/XCTest does not work under CLT** — but `swift run <Runner>` does
  (the spike ran green). The whole strategy routes through executable targets, never
  `swift test`.
- **`ImageRenderer` runs fully headless under CLT** — no Xcode, no window server, no
  `NSApplication`. Two independent checks produced **byte-identical** PNGs. Because it
  creates **no `NSWindow`**, the "CI image is 167px shorter than local" title-bar class
  of snapshot bug simply can't happen.
- **`.accessibilityIdentifier()` is queryable from a separate non-Xcode process** via
  `AXUIElementCopyAttributeValue(_, "AXIdentifier")` — verified read→press→assert with
  zero coordinates. (Apple's docs frame AX ids as test-only; that's wrong on macOS.)
- **All third-party test libs are off the table by mechanism, not taste:**
  swift-snapshot-testing, XCUITest, Quick/Nimble all transitively `import XCTest`;
  swift-testing needs `import Testing` — none build under CLT. The only "vendored
  dependency" is the in-repo ~150-line XCTest shim. **Zero runtime deps stays intact.**

## The honest wall: Layer 3 can't run on hosted CI

The AX driver process needs the **Accessibility TCC grant**. Locally / on a
self-hosted Mac with a logged-in user this **works** (verified), and a stable-identity
signed harness keeps the grant across runs (the same sticky-grant trick the applet
already uses). On **GitHub-hosted** macOS runners it **cannot**: SIP is enabled, so
`TCC.db` writes don't take, and there's no UI to click Allow. This is confirmed
unsolved upstream — not worth fighting. So Layer 3 lives as either:

1. a **self-hosted Mac** runner (`[self-hosted, macos, e2e]`), e2e job on `main` +
   `e2e`-labelled PRs — needs a stable signing identity so the TCC grant survives; or
2. a scripted **`make e2e` maintainer pre-merge gate** (matches CLAUDE.md's existing
   "awaiting maintainer Mac verification" posture), with the AX-walking *logic* unit-
   tested in Layer 1 against a committed AX-tree fixture for free CI coverage.

**Recommendation:** start with (2) — no new infra, matches today's posture — and treat
the self-hosted Mac as a later upgrade if e2e earns its keep.

## CI plan (additive — don't rewrite existing files)

- **Kept on ubuntu (free, every PR, blocks):** shellcheck/actionlint, the bash suite
  (+ new per-verb tests), the assemble build. Optionally mirror the SwiftUI-free
  `ProfilesCore` logic tests to Linux for free coverage.
- **New macOS job:** `xcode-select -s …/CommandLineTools` (force CLT so CI fails the
  way a CLT-only contributor would), cache `.build` keyed per-OS (never share across
  macos-14/15), `swift build`, then `swift run ProfilesCoreTests` and
  `swift run ProfilesSnapshotTests` (upload diff PNGs on mismatch). Tests need **no
  signing** (ad-hoc or none) — the 6 Developer-ID/notarization secrets stay
  exclusively in `release.yml`.
- **Triggers:** PR → single `macos-latest`; release → macos-14 + 15; weekly cron →
  full matrix. **Cost:** a few dollars/month now (macOS minutes bill 10×), **zero once
  the repo is public** (Actions free) — at which point add `push: main`.

## Testability seams (extract these FIRST)

1. `protocol EngineRunning` — `EngineClient` (real `Process`) vs `FixtureEngine`
   (canned `[ProfileStat]`/throws); `StatsStore.init` takes `any EngineRunning`.
2. `protocol PollClock` — real 2s sleep vs `ImmediateClock`; tests drive N polls
   instantly, no wall-clock flake.
3. A **`ProfilesCore` module that does not import SwiftUI** — holds `PtmxHysteresis`,
   formatters, `sortProfiles`, `ProfileStat.decodeList`, slug special-casing. Views
   import Core; Core never imports views.
4. Snapshot views take an explicit **fixture model + frozen data** as init params (no
   `@Environment`, no `Date.now`, no materials).
5. Cross-cutting: a stable `.accessibilityIdentifier()` on **every** control — a
   coding convention from day one (costs nothing, is the pixel-free addressing layer).

## How it folds into the build (TDD-first)

Harness + CI **before** features, so every feature lands already covered:
1. Lift the spike's `Package.swift` layout + XCTest shim + TestRunner into the real
   package as production `ProfilesCoreTests` / `ProfilesSnapshotTests`.
2. Stand up the macOS CI job green on a near-empty package (gate works before code).
3. Extract the four seams as the foundation.
4. Build features test-first — **`PtmxHysteresis` first** (crafted tick sequences:
   escalate only ≥90% after N consecutive ticks, de-escalate only below 80%, boundary
   arithmetic), then decode (from the captured-real fixture), formatting, sort, store.
5. Each leaf view ships its Layer-2 golden in the same PR.
6. `.accessibilityIdentifier()` on every control as authored.
7. Defer Layer 3 wiring until views stabilize; capture an AX-tree fixture early.

Carry the CLAUDE.md rule verbatim: **every new `engine.sh` verb gets a bash test in
the same PR** — the `FixtureEngine` does not absolve this (the fake proves Swift
decodes; the bash test proves the real producer emits).

## Open risks (flagged honestly)

1. **Cross-runner snapshot drift (dominant).** Same-machine byte-stability was proven,
   but GitHub images differ (M1 vs Intel, macos-13/14/15) and get deprecated on a
   schedule. Pin an **exact** runner image, bless goldens on it, keep a `sips` dimension
   pre-check, treat an image bump as a reviewed `--record` PR. Don't drop tolerance
   below ~95% to force-pass — that masks real regressions.
2. **Layer 3 has no hosted-CI home** — structural (SIP/TCC), not a bug. Without a
   self-hosted/auto-login Mac, real window-raise/sheet-creates coverage stays manual.
3. **Layer 3 is the flakiest, least-proven layer** — the AX loop was verified on a toy
   app, not the full `NavigationSplitView`/`.inspector`/`MenuBarExtra` scene. It
   deserves its own small spike before being relied on; always poll-with-timeout (2s
   poll + async render), never assert instantly.
4. **Vibrancy/material surfaces** (vibrant sidebar, `.regularMaterial`) are
   non-deterministic headless → **eyeball-only**, no snapshot coverage by design.
5. **`@MainActor` plumbing** (the spike's friction) recurs in the snapshot renderer and
   store tests — budget for `MainActor.assumeIsolated`.
6. A future self-hosted e2e Mac needs **stable-identity signing** so its TCC grant
   survives across builds — a small infra prerequisite.
