# Changelog

## [Unreleased]

## [0.4.0] — 2026-06-15
- **Much snappier dashboard (performance fix).** The 2s live-stats refresh no
  longer freezes the window. Two causes were fixed: (1) the stats sweep ran
  **synchronously on the applet's main thread**, blocking the WebView for ~0.4s
  out of every 2s — it now runs in the background and the UI reads the last
  completed snapshot (atomic file swap), so the main thread never waits on it;
  (2) `engine.sh stats` spawned a full-system `ps` per profile per metric (4+
  per tick, scaling with profile count) — it now takes **one** `ps` snapshot per
  tick and shares it across all helpers (O(1) instead of O(profiles)). `lsof`
  calls also gained `-nP` to skip host/port name resolution. An open terminals
  drill-down (which re-requests `terminals <slug>` every tick) got the same
  background treatment: it now reads the last completed result and refreshes in
  the background, with a one-time synchronous fetch on first open so the table
  still paints instantly.
- **Smooth scrolling — the grid no longer rebuilds every tick.** The dashboard
  used to recreate every card's DOM via `innerHTML` on each 2s refresh, which
  reset scroll position and hover state mid-gesture. It now rebuilds only when
  the card *structure* changes (a profile appears/disappears, flips
  running↔stopped, or you expand/confirm something); on a steady tick it patches
  just the numbers and sparkline points in place. An open terminals panel
  likewise patches only its own table, not the whole grid.
- **Fixed lag while a terminals panel was open (the big one).** A feedback loop
  in the JS↔native title bridge: an open drill-down keeps itself live by setting
  `document.title = "cp:terminals:<slug>"` each tick, and the 250ms bridge poller
  was responding by kicking off another full stats push — which re-set the title,
  which the next poll caught… so the refresh+rebuild cycle ran ~4× per second
  whenever a panel was open. The bridge now skips that follow-up push for the
  panel's own auto-refresh, dropping it back to the intended 2s cadence. The
  dashboard also defers DOM updates while you're actively scrolling.
- **Scroll jank fix.** The transient toast banner used `position: sticky`, which
  can force WebKit off threaded (GPU) scrolling onto the main thread. It's now
  `position: fixed`, keeping toasts visible without the scroll penalty.
- **Per-profile Dock icons.** Each profile wrapper now gets a distinct icon —
  Claude's real icon badged with the profile's initial on a deterministic
  colored disc — so accounts are tellable apart in the Dock, Spotlight, and
  ⌘-Tab while still reading as Claude. Generated zero-dependency via an
  AppleScriptObjC compositor; `engine.sh rebadge <slug>` reapplies it to
  existing profiles. Badged icons are produced locally and never committed.
- New app icon for the manager itself (window-stack mark), baked zero-dependency
  (`scripts/make-icon.sh`, `sips`).
- CLI `clean <Name>` — clear a stopped profile's regenerable caches (running-guarded).
- `scripts/sign.sh` — code-sign + notarize + staple the app/DMG for distribution.

## [0.3.0] — 2026-06-12

### Per-instance drill-down
- Running profile cards expand in place (full grid width) to a live table of
  the instance's terminal sessions — device, command, and idle time — with a
  per-row **Close** (arm-then-confirm) that sends a hangup to that terminal's
  session. The open panel refreshes every tick.
- Stopped profile cards expand to granular cleanup tiers — Caches / GPU /
  Logs / Everything — so you can free one cache class without nuking the rest.
- **Throttle CPU**: lower a running instance's process-tree priority (renice
  +10) to tame a CPU hog without force-quitting. One-way until relaunch
  (unprivileged users can't restore niceness), and labeled as such.
- Engine: `terminals`, `closeterm`, `throttle` subcommands. Terminal close
  and throttle are guarded to the instance's own process tree — they can
  never touch another instance or an arbitrary process.

### Settings & automation (opt-in, off by default)
- A Settings panel with two local, never-networked automation knobs:
  auto-clean stopped profiles over a chosen disk limit, and auto-close
  terminals idle past a chosen threshold (with a clear caveat that a silent
  long-running task can read as idle).
- Engine: `getconfig` / `setconfig` (validated, persisted under
  `.runtime/settings`) and `autotick`, enforced by the applet every ~16s and
  a cheap no-op while disabled.

### Cleanup
- Cleanup button in the dashboard header: a modal with graceful quit-all,
  cache-clear for all stopped profiles, and Emergency Stop — a killswitch
  that force-quits every Claude instance (default included) for when the
  machine is overloaded. Arm-then-confirm, 3-second disarm. All sign-ins
  and data survive every option.
- Per-tier clean (`clean <slug> [caches|gpu|logs|all]`).
- Engine: quitall / cleanall / killswitch subcommands.

### Trustworthy metrics (attribution hardening)
- Per-instance stats can no longer bleed across apps: `--user-data-dir` is
  matched as a complete argv value (a profile whose data dir is a prefix of
  another's no longer absorbs the sibling's CPU/memory/terminals), and
  terminals are counted by distinct device (a tty shared across Electron
  processes counts once). Each terminal is provably attributed to one
  instance.

### Default instance
- The stopped default-instance card gains an **Open** action (`opendefault`,
  `open -n -a`) to launch the base Claude. Its data dir stays off-limits.

### Stability & polish
- Dashboard applet has a stable identity: stripped `Assets.car` /
  `CFBundleIconName` so the Dock shows the real icon, a fixed
  `CFBundleIdentifier`, and applet reuse when the source is unchanged (which
  keeps the one-time Automation grant from being revoked each launch — fixes
  Show Window across Spaces). macOS 14+ activation handoff before Show Window.
- Button hover / press / keyboard-focus states across the UI; a startup
  loading screen until the first stats render.
- New app icon: a "window stack" mark (cascading app windows on the dark
  squircle) in the dashboard palette, trademark-safe. Source SVG plus a
  zero-dependency bake script (`scripts/make-icon.sh`, macOS `sips` only).

### Tests
- Suite grows to 80 checks (engine sourceable for unit tests; new coverage
  for attribution isolation, terminals, closeterm/throttle tree guards, clean
  tiers, settings round-trip + auto-clean, and dashboard render).


## [0.2.0] — 2026-06-12
Consistent UI: the dashboard is now the app.
- Launching opens the dashboard window directly; the dialog menu is demoted
  to an automatic fallback (or `--classic` for scripting).
- New Profile is an in-window form; Remove is an in-card two-step flow with
  the typed-DELETE safeguard, all in the dashboard aesthetic.
- Engine gains headless `create` / `remove` / `purge` subcommands.
- UI edits pause live re-rendering so confirmation steps can't be interrupted.


## [0.1.0] — 2026-06-12
Initial release (Apache-2.0).
- Multi-account profiles: generated native wrapper apps, one per account,
  each permanently signed in via its own `--user-data-dir`.
- GUI manager app (native dialogs, no terminal): add / open / remove with
  typed-DELETE protection for saved logins.
- Native dashboard window (osascript + WKWebView): live CPU / memory /
  process / PTY / disk per instance with rolling sparklines, 2 s refresh.
- Show Window: raise all windows of a specific instance by PID
  (NSRunningApplication; works across shared bundle IDs, no permissions).
- Cleanup utilities: graceful quit, force-quit (full tree), cache clearing
  with running-instance refusal and login preservation.
- Local-only usage stats (`.profile-activity`, last 50 launches). No
  telemetry, no network I/O.
- Automatic fallback to dialog UI if the dashboard window can't open.
- CLI (`cli/claude-profiles.sh`) incl. Claude Code `CLAUDE_CONFIG_DIR` aliases.
- 22-test Linux-compatible suite; CI via GitHub Actions.
