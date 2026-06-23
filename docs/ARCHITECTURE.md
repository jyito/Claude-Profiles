# Architecture

This document explains how Claude Profiles works end to end, and why each
design decision was made. There are three parts: the generated **profile
wrappers** (tiny bash `.app`s), the **`engine.sh`** data/actions backend (bash,
macOS built-ins), and the **native SwiftUI app** (`app/`) that is the user-facing
dashboard. The SwiftUI app is compiled with the Command Line Tools (no Xcode)
and pulls in no third-party SwiftPM packages; `engine.sh` stays pure bash.

## 1. Profile wrappers — the core trick

Claude Desktop (Electron/Chromium) accepts `--user-data-dir=<path>` and keeps
**all** session state there: auth tokens, cookies, localStorage, IndexedDB,
MCP configuration. Two instances pointed at two directories are, to Claude's
servers, two independent installations.

A profile is therefore just a generated bundle (written by `engine.sh`'s
`create`, not a separate manager binary):

```
~/Applications/Claude Business.app/
  Contents/
    Info.plist            # CFBundleIdentifier: local.claude-profiles.business
    MacOS/launcher        # short bash script (the entire executable)
    Resources/app.icns    # badged copy of the real Claude.app icon
```

The launcher, in essence:

```bash
DATA_DIR="$HOME/.claude-instances/business"
date '+%Y-%m-%d %H:%M' >> "$DATA_DIR/.profile-activity"   # local-only stats
exec /usr/bin/open -n -a "/Applications/Claude.app" --args --user-data-dir="$DATA_DIR"
```

Design points:

- `open -n` forces a new process even when another instance is running.
- Unique `CFBundleIdentifier` per wrapper keeps Spotlight/Dock/Launchpad
  treating each profile as a distinct app.
- `LSUIElement=true` stops the short-lived wrapper process from bouncing in
  the Dock (the launched Claude shows its own icon).
- The launcher re-detects Claude.app if the recorded path disappears (e.g.
  after a relocation) and shows an error dialog rather than failing silently.
- Bundles are generated **locally**, so they carry no quarantine attribute:
  no Gatekeeper prompts for generated profiles.
- Hostile profile names are sanitized (quotes/braces stripped) before being
  embedded in plists, scripts, or AppleScript strings.

**Credentials are deliberately out of scope.** The data dir *is* the
credential store, managed by Claude Desktop itself. The launcher never reads,
writes, or proxies a token, and never scripts the login UI.

## 2. The manager — native SwiftUI app (`app/`)

The user-facing manager is a native SwiftUI app, built from the SwiftPM package
in `app/` with the Command Line Tools (no Xcode). The compiled `Profiles`
binary plus `engine.sh` + `badge-icon.applescript` are assembled into
`Claude Profiles.app` by `scripts/build.sh`. The package is three layers:

- **`ProfilesCore`** — pure logic, no SwiftUI. The engine seam lives here:
  `EngineRunning` (a protocol abstracting "run the bash engine") and `PollClock`
  (the tick abstraction) are the test seams; `EngineClient` is the real
  implementation that shells out to `engine.sh` with `Process` and `Codable`-decodes
  its JSON. The `@Observable` `StatsStore` holds live state and drives the 2-second
  poll. Models (`ProfileStat`, `ProfileConfig`, `RemoteInfo`, `TerminalInfo`),
  the leak-gauge state machine (`PtmxHysteresis`), `BadgePreview`, `Sort`, and
  `Formatters` round it out. `FixtureEngine` supplies canned data so the UI and
  snapshot tests never touch a live engine.
- **`ProfilesUI`** — the `Theme` and every view: `ProfileCardView` (live card
  with `Sparkline` + `HandleGauge`), the vibrant `SidebarView` (`VisualEffectView`),
  `KPIStripView`, the master-detail `ProfileDetailView` (three hero trend charts —
  CPU / Memory / handle-pool-toward-ceiling — plus a `LeakBlock` verdict), the
  drill-down (`InstanceSections` / `TerminalsTable` / `CleanTiers`), the modal
  sheets (`NewProfileSheet` with a live badge preview, `SettingsSheet`,
  `CleanupSheet`, `RemoteSheet` with a `QRCode`), `MenuContent` (the MenuBarExtra
  switcher), and `Focus` (Show Window by PID).
- **`Profiles`** (executable) — the `@main` SwiftUI `App` (`ProfilesApp`) with
  its `NavigationSplitView` + `MenuBarExtra` scene, `DashboardView`, and
  `EnginePath` (`resolveEnginePath()` finds the bundled `engine.sh`, falling back
  to `Bundle.main.resourcePath`).

The scene owns every engine call; the views are pure (fixtures + closures) so
they render under the snapshot harness without a backend. Removing a profile
requires typing `DELETE` to erase a saved login — the data dir is treated as
precious by default. The same flows are reachable headlessly through
`cli/claude-profiles.sh`, which drives the same `engine.sh`.

## 3. The engine (`src/engine.sh`)

A small data/actions backend. It is the SwiftUI app's only backend (invoked via
`Process`, output decoded with `Codable`) and is also driven directly by
`cli/claude-profiles.sh`. There is no other bridge — the typed `Process` +
`Codable` boundary replaces the old WebView `document.title` title-polling.

**Process attribution.** An instance's main process is found by matching its
`--user-data-dir=` argument in `ps axo pid=,command=` as a *complete* argv
value — the character after the directory must be a space or end of line.
(A substring match would let a profile whose data dir is a prefix of another's,
e.g. `work` vs `work2`, absorb the sibling's processes and corrupt every
per-instance metric.) Electron helper processes (renderer, GPU) don't reliably
carry that flag, so the engine walks the full child tree from the main PID
(`tree_pids`, iterative parent-set expansion over a single `ps` snapshot). CPU
and RSS are summed across the tree; PTY handles are counted via `lsof` matching
`/dev/ttys`, deduplicated by device so a tty shared between the main process
and a helper is counted once. Each `/dev/ttys` is therefore attributed to
exactly one instance.

**Disk.** `du` over multi-gigabyte profile dirs is too slow for a 2-second
tick, so sizes are cached for 30 seconds in `$TMPDIR`.

**Stats output** is a JSON array, one object per profile plus the default
Claude instance, e.g.:

```json
{"name":"Claude Business","slug":"business","running":true,
 "cpu":16.8,"mem":896,"procs":3,"ptys":3,"disk":480,
 "ptmx":7,"ptmxMax":511,"remote":false,
 "opens":12,"last":"2026-06-10 08:12"}
```

`ptmx` is the count of leaked `/dev/ptmx` master handles held (NOT deduped — vs
`ptys`, the deduped count of real terminals), and `ptmxMax` is the system ceiling
(`sysctl -n kern.tty.ptmx_max`), so the dashboard can warn before the pool
exhausts. `remote` is whether that profile's Claude Code `screen` session is live.

**Actions**: `open`, `quit` (TERM to the main process; Electron shuts helpers
down cleanly), `force` (KILL to the whole tree — releases stuck PTYs),
`restart` (TERM-wait-KILL-relaunch — the only way to reclaim the leaked
`/dev/ptmx` masters), `focus` (raise an instance's windows by PID),
`create`/`remove`/`rebadge` (wrapper bundle + badged icon lifecycle),
`clean` (deletes only regenerable Electron caches: `Cache`, `Code Cache`,
`GPUCache`, `Dawn*Cache`, `ShaderCache`, completed crash dumps — **never**
`Cookies`/`Local Storage`, and refuses entirely if the instance is running),
`terminals`/`closeterm`/`throttle` (drill-down: list / hang up / renice, each
guarded to the instance's own tree), `getconfig`/`setconfig`/`autotick` (the
opt-in auto-clean / auto-close settings), `remoteinfo`/`copy` (the Remote sheet),
and `mainpid`/`defaultpid` (PID lookup for window focusing). Cache deletion
paths are guarded with `${var:?}` so an empty variable can never expand to
`rm -rf /...`.

## 4. The dashboard (native SwiftUI, `app/`)

The dashboard is a compiled native SwiftUI app — no WebView, no AppleScript
title-bridge. It is the `Profiles` executable described in §2; this section is
how it talks to the engine and raises windows.

- **Engine boundary — `Process` + `Codable`.** `EngineClient` runs
  `engine.sh <verb> [args]` through `Foundation.Process` (executable
  `/bin/bash`, stderr routed to `/dev/null` so an undrained pipe can't deadlock
  `waitUntilExit()`) and decodes the JSON output into typed Swift models with
  `Codable`. Action verbs that exit 0 on failure (printing an error token like
  `refused` / `err …`) are surfaced as thrown errors so a failed action never
  reports success. This is a real typed boundary — no string-polling bridge.

- **Live polling.** The `@Observable StatsStore` (in `ProfilesCore`) runs
  `engine.sh stats` every 2 seconds on a `PollClock`, keeps a 30-point rolling
  CPU/memory history per profile for the sparklines and hero charts, and drives
  the leak gauge through the `PtmxHysteresis` state machine. One store instance
  is shared by the window scene and the `MenuBarExtra`, so their running dots
  match by construction (no second poll loop).

- **Window focusing (Show Window).** `Focus.show(pid:)` resolves the instance's
  main PID via the engine (`mainpid` / `defaultpid`), then calls
  `NSRunningApplication runningApplicationWithProcessIdentifier:` and
  `activateWithOptions:`. PID-level targeting is what makes this work despite all
  instances sharing Claude's bundle ID. macOS 14+ cooperative activation can
  ignore the request (other Spaces/displays/fullscreen); the System Events
  frontmost fallback then triggers the one-time Automation prompt — the only
  permission in the project.

- **Purity.** The scene (`ProfilesApp`) owns every engine call; the views are
  pure functions of `ProfileStat`/fixtures plus callback closures. That keeps the
  whole UI renderable headlessly under the snapshot harness with no live backend.

## Testing strategy

Two layers, both runnable without full Xcode:

- **Bash / engine suite — `tests/run-tests.sh`** runs on Linux or macOS by
  shimming `ps` (a fixed fake process table with two instance trees), `lsof`,
  `defaults`, and friends. It exercises engine JSON correctness (tree-summed
  CPU/MEM, deduped PTY counts), process attribution (the `work` vs `work2`
  prefix trap), PID resolution, the wrapper-create flow with data preservation,
  name sanitization, and the cache-clean safety rails.

- **Swift suite — executable runners.** `swift test` needs full Xcode, so the
  Swift layers run as plain executables under the Command Line Tools:
  `swift run ProfilesCoreTests` (Layer-1 logic, via a small vendored `XCTest`
  shim) and `swift run ProfilesSnapshotTests` (Layer-2 golden-PNG proof:
  `ImageRenderer` → PNG diffed against `app/Tests/__Snapshots__/*.png` within a
  per-case tolerance). The view layer is fixture-driven, so these render every
  card / sheet / detail page without a live engine.

The one layer that still can't be exercised off-macOS is the running SwiftUI
window (AppKit/WebKit-free but still macOS-only); changes there should be checked
on a real Mac, with the macOS version noted in the PR.

## Threat model notes

- The engine executes nothing it didn't generate; profile names are sanitized
  before being templated into wrapper bundles.
- No network I/O anywhere in this codebase.
- `rm -rf` sites are parameter-expansion-guarded (`${var:?}`).
- The app never elevates privileges and writes only under `~/Applications`,
  `~/.claude-instances`, and `$TMPDIR`.
- Modifying Claude.app itself is explicitly out of scope (it would break its
  code signature).
