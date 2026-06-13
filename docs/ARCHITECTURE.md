# Architecture

This document explains how Claude Profiles works end to end, and why each
design decision was made. The system has four components, all plain text
files, no compilation anywhere.

## 1. Profile wrappers — the core trick

Claude Desktop (Electron/Chromium) accepts `--user-data-dir=<path>` and keeps
**all** session state there: auth tokens, cookies, localStorage, IndexedDB,
MCP configuration. Two instances pointed at two directories are, to Claude's
servers, two independent installations.

A profile is therefore just a generated bundle:

```
~/Applications/Claude Business.app/
  Contents/
    Info.plist            # CFBundleIdentifier: local.claude-profiles.business
    MacOS/launcher        # short bash script (the entire executable)
    Resources/app.icns    # copied from the real Claude.app at creation
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

## 2. The manager (`src/launcher`)

The manager is itself one of these bundles. Its launcher is a larger bash
script that drives native macOS dialogs via `osascript` (`choose from list`,
`display dialog`), so end users never touch a terminal. It implements:

- create / open / remove profiles (remove requires typing `DELETE` to erase a
  saved login — the data dir is treated as precious by default)
- a classic dialog-based activity view (also the dashboard's fallback)
- `--action add|remove` argv dispatch so the dashboard window can reuse the
  dialog flows
- first-run icon bootstrap (copies Claude's `.icns` into itself)

Dialog strings escape embedded quotes and convert newlines to AppleScript
`\n` escapes (`esc_msg`). Every dialog displays the app icon (`dialog_icon`).

## 3. The engine (`src/engine.sh`)

A small data/actions backend used by both UIs.

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
 "opens":12,"last":"2026-06-10 08:12"}
```

**Actions**: `open`, `quit` (TERM to the main process; Electron shuts helpers
down cleanly), `force` (KILL to the whole tree — this is what releases stuck
PTYs), `clean` (deletes only regenerable Electron caches: `Cache`,
`Code Cache`, `GPUCache`, `Dawn*Cache`, `ShaderCache`, completed crash dumps —
**never** `Cookies`/`Local Storage`, and refuses entirely if the instance is
running), `mainpid`/`defaultpid` (PID lookup for window focusing). Cache
deletion paths are guarded with `${var:?}` so an empty variable can never
expand to `rm -rf /...`.

## 4. The dashboard (`src/dashboard.html` + `src/dashboard.applescript`)

The dashboard is a real native window without compiled code:

- `dashboard.applescript`, run by `/usr/bin/osascript`, uses AppleScriptObjC
  (`use framework "AppKit"/"WebKit"`) to create an `NSWindow` containing a
  `WKWebView` that loads `dashboard.html` from the bundle's Resources.

- **JS → native bridge:** AppleScriptObjC can't implement
  `WKScriptMessageHandler` (no class subclassing) or completion-handler
  blocks. Instead, page buttons set `document.title = "cp:verb:slug"`. The
  window title is a KVO-readable property, so a 0.5 s `NSTimer` (script
  objects *can* be timer targets) polls it, resets it, and dispatches the
  action — no blocks, no subclasses, no permissions.

- **Native → JS:** every 4th tick (2 s), the timer runs `engine.sh stats` via
  `do shell script` and injects `updateStats(<json>)` with
  `evaluateJavaScript:completionHandler:(missing value)` (fire-and-forget is
  allowed without a block).

- **Window focusing:** `cp:focus:<slug>` resolves the instance's main PID via
  the engine, then calls `NSRunningApplication
  runningApplicationWithProcessIdentifier:` and `activateWithOptions:3`
  (activate-all-windows | ignoring-other-apps). PID-level targeting is what
  makes this work despite all instances sharing Claude's bundle ID, and it
  requires no Accessibility/Automation consent.

- **Lifecycle:** closing the window (not minimizing — both `isVisible` and
  `isMiniaturized` are checked) terminates the host. If the host exits
  abnormally within ~4 s of launch, the manager falls back to the dialog
  activity view automatically.

- The HTML keeps 30-point rolling CPU/memory histories per profile and draws
  sparklines as inline SVG polylines. No external resources are loaded; the
  page works fully offline (matching the no-network guarantee).

## Testing strategy

`tests/run-tests.sh` runs on Linux or macOS by shimming `osascript` (canned
dialog responses from a queue), `defaults`, `ps` (a fixed fake process table
with two instance trees), and `lsof`. This exercises: dialog lifecycle flows,
idempotent re-add with data preservation, name sanitization, engine JSON
correctness (tree-summed CPU/MEM, PTY counts), PID resolution, cache-clean
safety rails, and the dashboard JS render path under Node.

The one layer that cannot run off-macOS is `dashboard.applescript` (~120
lines). It follows canonical AppleScriptObjC patterns and is protected by the
runtime fallback; treat it as the first suspect for any window-related bug
report, and test changes to it on real macOS.

## Threat model notes

- The launcher executes nothing it didn't generate; profile names are
  sanitized before templating.
- No network I/O anywhere in this codebase.
- `rm -rf` sites are parameter-expansion-guarded.
- The manager never elevates privileges and writes only under
  `~/Applications`, `~/.claude-instances`, and `$TMPDIR`.
- Modifying Claude.app itself is explicitly out of scope (it would break its
  code signature).
