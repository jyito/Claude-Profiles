# Changelog

## [Unreleased]

## [0.7.1] — 2026-06-23

- **Fixed:** quitting the **default** Claude instance left its card stuck on "Running"
  with a dead Show Window button. The default card now flips to a **Stopped** state with
  an **Open** button (relaunches via the engine's `opendefault`); the detail-page action
  bar does the same. The restricted-default contract is unchanged (no clean/details/disk).

## [0.7.0] — 2026-06-22

The dashboard is now a **native SwiftUI app** — a full rewrite replacing the
AppleScriptObjC + WebView host. Built with the Command Line Tools (no Xcode),
zero runtime dependencies, signed + notarized. `engine.sh` stays the bash backend.

- **New:** native split-view window with a permanent vibrant sidebar. The card
  grid is the overview; clicking a profile opens a **maximized detail page** with
  a back button — no more squeezing side panel.
- **New:** the detail page shows three hero trend lines — CPU, Memory, and the
  **handle pool climbing toward its ceiling** with a leak verdict (✓ healthy /
  ▲ climbing — restart soon) — plus a stat strip (procs · terminals · disk ·
  opened · last launch · remote) and the terminals table / Throttle / clean
  tiers / badge / Remove.
- **New:** live cards with CPU/Memory sparklines + the handle-leak gauge, a
  functional menu-bar switcher, Show Window across Spaces (in-process focus by
  PID), and the modals — New Profile (with a live badge-disc preview), Settings,
  Cleanup, and Remote (SSH commands + a scannable QR).
- **Changed:** the app shells out to `engine.sh` via `Process` + typed `Codable`
  decoding, replacing the old `document.title` title-bridge.
- **Removed:** the AppleScriptObjC applet + the WebView `dashboard.html` host.
- **Build:** `cd app && swift build`; tests are executable runners under the
  Command Line Tools (`swift run ProfilesCoreTests` / `ProfilesSnapshotTests`,
  since `swift test` needs Xcode) alongside the bash `tests/run-tests.sh`.

## [0.6.2] — 2026-06-21
UI polish.
- **Fixed:** the transient status toast ("Launching…", etc.) moved from the top-right (where it overlapped the New Profile button) to an upper-left pill that stays clear of the buttons.

## [0.6.1] — 2026-06-20
Patch on top of the first signed release.
- **Fixed:** the system-wide leak banner now aligns with the profile cards and has a gap below it (was inset 22px and flush against the grid).

## [0.6.0] — 2026-06-20

First signed + notarized release (Developer ID). Downloads open with a normal
double-click — no Gatekeeper "Open Anyway" detour.

### Terminal-handle leak (the `/dev/ptmx` wedge)
- **Detection + cleanup.** Claude Desktop leaks `/dev/ptmx` master handles (one per
  terminal session, never released); enough of them across instances exhausts the
  system pool (`kern.tty.ptmx_max`) and can wedge the whole Mac. The dashboard now
  counts them per instance and shows a **"N leaked"** stat on the card's status line
  — visible on the collapsed card whenever there's any leak, brightening once it
  crosses the threshold (~50) where a restart is worth doing. The cleanup lives in
  **+ Details**: a two-step **Restart to free handles** (arm → confirm) warning that
  it quits and reopens Claude (windows + running terminals close; login and saved
  chats are kept). A top banner appears only in a true system-wide emergency (≥80%
  of the ceiling). Restart cycles just that instance (TERM → wait → force → relaunch)
  — the only way to reclaim the handles, since you can't free another process's fds
  from outside. New engine `restart <slug>` action and `ptmx`/`ptmxMax` stats fields;
  new `cp:restart` bridge verb.
- **Opt-in auto-restart.** Settings can auto-restart a profile once it crosses a
  chosen leaked-handle threshold (`autoRestartLeakAt`, default off), enforced by the
  existing `autotick` sweep. Profiles only — never the default.

### Switching
- **Menu-bar switcher.** A persistent menu-bar item lists every account (running ones
  marked ●); click one to focus or launch it without opening the dashboard, plus
  Show Dashboard / Quit. Closing the dashboard window now hides it to the menu bar
  (Quit via the menu or ⌘Q). New engine `menulist` command.
- **Keyboard switching.** ⌘⌥1–9 focuses the Nth instance while the dashboard is
  focused; a copy-paste Hammerspoon recipe (`docs/HOTKEYS.md`) drives a new headless
  `engine focus <slug>` for the same chord globally — zero-dependency, the app ships
  no global hooks.

### Remote
- **Live session status** — a mint dot on each card's Remote button marks accounts
  whose Claude Code `screen` session is already running (new `remote` stats field).
- **QR of the attach line** — the Remote modal renders a QR of the SSH attach line
  (a self-contained, zero-dependency byte-mode QR encoder) so you can read it onto a
  phone/iPad camera.

### Docs
- README refreshed with the new features + roadmap; `docs/SIGNING.md` and a draft
  Homebrew cask groundwork for signed distribution (blocked on an Apple Developer
  account).

## [0.5.1] — 2026-06-16
- **Remote on the default card too**, with a terminals-only **+ Details** view
  (the default never exposes Cleanup — its data dir stays off-limits).
- **Clearer Remote modal** — spells out it's Claude Code (terminal), not the
  Desktop chat window, and that each profile keeps its own isolated login.
- **Fixed:** a profile name containing `< > &` (e.g. "Q&A") produced a corrupt
  app that silently never appeared — those characters are now stripped, and
  `default` is reserved.
- **More robust startup** — if the dashboard window can't open on a given macOS,
  the error now offers a working **Use Simple Menu** button (the dialog menu),
  instead of telling you to pass a flag a downloaded app can't.
- **Verifiable downloads** — releases publish `SHA256SUMS.txt` and include the
  checksums in the notes.
- **Docs** — corrected install/Gatekeeper steps (on macOS 15+ use System Settings
  → Privacy & Security → **Open Anyway**; the right-click→Open shortcut was
  removed), rewritten to the real dashboard UI, with a stated **macOS 14+**
  requirement.

## [0.5.0] — 2026-06-15
- **Remote button on every profile card.** Make a profile reachable from another
  device without the CLI: the button starts/reuses its Claude Code session and
  opens a modal with copy-paste SSH commands (same-network and, when Tailscale is
  up, any-network) plus an in-app iPad/Tailscale setup guide. Copy buttons use a
  `pbcopy` bridge. New engine actions `remoteinfo` (JSON) and `copy`; new
  `cp:remote` / `cp:copy` bridge verbs. Still zero-network — the app opens no
  socket; SSH stays your own channel.
- The drill-down trigger is now a button-styled **+ Details** control (was a
  text-link "Terminals/Cleanup"); the terminal count stays in the status line.
- **`remote` reaches any device, anywhere.** When Tailscale is running, `remote`
  now auto-prints a works-from-any-network SSH attach line (using your Tailscale
  address) alongside the same-network one; when it's absent, it points you at
  installing it. Still zero-server — the app opens no socket; SSH is your own
  channel. (Genericized the example host in `docs/REMOTE.md`.)

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
