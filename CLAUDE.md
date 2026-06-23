# CLAUDE.md — Claude Profiles project context

Read this fully before making changes. It carries the context from the
original development sessions; the reasoning below was paid for in real
debugging on real macOS.

## What this is

Multi-account Claude Desktop for macOS. Each "profile" is a generated native
`.app` wrapper that launches the real Claude.app with its own
`--user-data-dir`, so each account stays permanently signed in and any number
run simultaneously. The user-facing app is a **native SwiftUI dashboard**
(split-view with a permanent vibrant sidebar, KPI strip, master-detail profile
pages with hero trend charts + leak verdict, live cards with sparklines + a
handle-leak gauge, a MenuBarExtra switcher, Show Window focusing, cleanup
utilities) built with the Command Line Tools — no Xcode — and signed +
notarized. The bash `engine.sh` is still the data/actions backend. Status:
**v0.7.0 — native SwiftUI dashboard SHIPPED**, replacing the old
AppleScriptObjC + WebView host (retired at this cutover); maintainer-verified
on macOS, CI green, public repo `jyito/Claude-Profiles`.

## Non-negotiables (PRs violating these get declined)

1. **Never touch credentials.** No reading/storing/transmitting tokens,
   passwords, cookies, Keychain. The per-profile data dir IS the credential
   store, managed by Claude Desktop itself. Never script the login UI.
2. **Zero network I/O.** No telemetry, no update checks, nothing. Local-only
   stats (`.profile-activity`, last 50 launches) are the only "analytics."
3. **Zero RUNTIME dependencies** (macOS built-ins only at runtime): bash,
   osascript, ps, lsof, defaults, du, PlistBuddy, iconutil/sips. No
   Homebrew/Node/Python at runtime. The Swift toolchain (Command Line Tools —
   **no Xcode**) is required to BUILD the app, but the shipped bundle is a
   self-contained native binary + bundled `engine.sh`; it pulls no third-party
   SwiftPM packages. `engine.sh` itself keeps its zero-dep, bash-3.2 constraints.
   (Tests use node/python3 but degrade gracefully.)
4. **Never modify Claude.app** — breaks its code signature.
5. **The default data dir (`~/Library/Application Support/Claude`) is
   off-limits.** The default-instance card offers Show Window / Quit / Force
   Quit, plus **Remote** — process signals are fine, and Remote only spins up a
   *separate* Claude Code session under `~/.claude-code-instances/default` (never
   touching the default's data dir). Reads/writes of the default data dir are
   not allowed; Clean Caches and the drill-down (+ Details) must never appear on
   the default card.
6. **Profile data dirs are precious.** Destroying one requires the typed
   DELETE flow. Every `rm -rf` uses `${var:?}` guards.
7. **bash 3.2 compatibility.** macOS ships bash 3.2. No `declare -A`,
   `mapfile`, `${var,,}`, or negative substring lengths.

## Architecture

The manager app is the native SwiftUI package in **`app/`** (a SwiftPM
project). `engine.sh` + `badge-icon.applescript` (in `src/`) are the bash
backend, bundled into the app's Resources. A generated **profile wrapper**
is still a tiny `.app` whose executable is an inline bash `launcher` that runs
`open -n -a Claude.app --args --user-data-dir=<dir>` — written by `engine.sh`'s
`cmd_create` (NOT the retired manager `launcher`, which is gone).

- **`app/` (SwiftPM package)** — built with the Command Line Tools (no Xcode).
  Three library/exe layers:
  - **`ProfilesCore`** — pure logic, no SwiftUI. The engine seam:
    `EngineRunning` (protocol abstracting "run the bash engine") + `PollClock`
    (the tick abstraction) are the test seams; `EngineClient` shells out to
    `engine.sh` via `Process` and `Codable`-decodes its JSON (the replacement
    for the old `document.title` title-bridge — a real typed boundary now). The
    `@Observable` `StatsStore` holds live state and drives the 2s poll. Also:
    `ProfileStat`/`ProfileConfig`/`RemoteInfo`/`TerminalInfo` models,
    `PtmxHysteresis` (leak-gauge state machine), `BadgePreview` (mirrors
    `badge_color_for` so the New Profile sheet previews the disc), `Sort`,
    `Formatters`, `FixtureEngine` (canned data for snapshot/UI tests).
  - **`ProfilesUI`** — the `Theme` + all views: `ProfileCardView` (live card
    with `Sparkline` + `HandleGauge` leak gauge), the vibrant `SidebarView`
    (`VisualEffectView`), `KPIStripView`, the master-detail `ProfileDetailView`
    (three hero trend charts — CPU / Memory / handle-pool-toward-ceiling — plus
    a `LeakBlock` verdict), `InstanceSections`/`TerminalsTable`/`CleanTiers`,
    the `Sheets/` (`NewProfileSheet` with live badge preview, `SettingsSheet`,
    `CleanupSheet`, `RemoteSheet` with `QRCode`), `MenuContent` (the
    MenuBarExtra switcher), `Focus` (Show-Window by PID). Snapshot-renderable
    via `SnapshotMode`/`DashboardMode`.
  - **`Profiles`** (executable) — the `@main` SwiftUI `App`/scene
    (`ProfilesApp`), `DashboardView`, and `EnginePath` (`resolveEnginePath()`
    finds the bundled `engine.sh`, falling back to `Bundle.main.resourcePath`).
  - **Testing seams.** `swift test` needs Xcode, so tests run as **executable
    runners** under the Command Line Tools: `ProfilesCoreTests` (Layer-1 logic,
    via a vendored minimal `XCTest` shim) and `ProfilesSnapshotTests` (Layer-2
    golden-PNG proof: `ImageRenderer` → PNG → `pngdiff.py` against
    `app/Tests/__Snapshots__/*.png` within a per-case tolerance).
- **`engine.sh`** — data/actions backend, called by the SwiftUI app (`Process`
  + `Codable`) and by `cli/claude-profiles.sh`.
  `stats` emits a JSON array per profile + the default instance.
  Process attribution: main PID found by matching `--user-data-dir=<dir>` in
  `ps axo pid=,command=` as a COMPLETE argv value (the char after the dir must
  be a space or EOL) — a substring match let a profile whose data dir is a
  prefix of another's (`work` / `work2`) absorb the sibling's PIDs and corrupt
  every per-instance metric. Electron helpers collected by walking the child
  tree (`tree_pids`) since helpers don't carry the flag. CPU/RSS summed over
  the tree (CPU can exceed 100% — per-core semantics, same as Activity
  Monitor). PTYs counted via `lsof` matching `/dev/ttys`, DEDUPED by device (a
  tty shared by the Electron main + helpers must count once) — displayed as
  "terminals" in all UI copy (PTY is jargon; `ptys` stays as the JSON key and
  internal term). Disk via `du` cached 30s in `$TMPDIR` (live `du` on multi-GB
  dirs is too slow). The dispatch is guarded by a `BASH_SOURCE`==`$0` check so
  the test suite can source the file and unit-test the attribution functions.
  Actions: `open quit force restart focus clean create remove rebadge purge
  mainpid defaultpid quitdefault forcedefault opendefault terminals closeterm
  throttle getconfig setconfig autotick remoteinfo copy`. `focus <slug|default>`
  raises an instance's windows by PID (System Events frontmost) — the headless
  twin of the applet's in-process focus, for external callers like the optional
  Hammerspoon global-hotkey recipe (`docs/HOTKEYS.md`). `restart <slug>` (slug or
  `default`) cycles an instance — TERM the tree, wait ~5s, force-`kill -9` if
  still alive, then relaunch — the ONLY way to reclaim the `/dev/ptmx` master fds
  Claude Desktop leaks (you can't free another process's fds from outside; root
  cause confirmed — bundled node-pty 1.1.0-beta34, see
  `docs/postmortems/2026-06-21-ptmx-node-pty-leak.md`).
  `stats` also emits per-instance `ptmx` (leaked masters held, NOT deduped — vs
  `ptys`, the deduped real terminals) and `ptmxMax` (`sysctl -n kern.tty.ptmx_max`
  ceiling) so the dashboard can warn before the pool exhausts and wedges the Mac.
  `stats` also emits a per-instance `remote` boolean — whether that profile's Claude
  Code `screen` session (`claude-<slug>`) is live — via `remote_live`, fed by one
  `screen -ls` per tick (`SCREEN_SNAP`, dynamic scope); read-only, never starts a
  session. The card's Remote button shows a mint live-dot when true.
  `remoteinfo <slug>` starts/reuses the
  profile's Claude Code `screen` session (`~/.claude-code-instances/<slug>`) and
  emits JSON (`session`/`user`/`host`/`tailscaleIp`/`alreadyRunning`) for the
  dashboard's Remote modal — the GUI-facing twin of the CLI's text `remote`.
  `copy <text>` pipes to `pbcopy` for the modal's Copy buttons. `create`/`rebadge` give each wrapper a distinct Dock icon
  via `badge_icon`: Claude's real icns → base PNG → `badge-icon.applescript`
  compositor → iconset → `iconutil`, badging it with the profile's initial on a
  deterministic per-slug colored disc (`badge_color_for`, 6-colour palette that
  contrasts coral). Degrades to a plain copy of Claude's icns off-macOS/CI. The
  badged icon is generated locally at runtime and NEVER committed (trademark). `clean <slug> [caches|gpu|logs|all]` deletes only
  regenerable Electron caches and refuses if the instance is running.
  `terminals` emits `[{dev,pid,cmd,idle}]` (idle = now − tty device mtime).
  `closeterm`/`throttle` are guarded to the instance's own tree — never an
  arbitrary pid. `autotick` enforces the opt-in auto-clean / auto-close
  settings (stored under `.runtime/settings`), a cheap no-op while disabled.
- **`badge-icon.applescript`** — zero-dep AppleScriptObjC icon compositor called
  by `engine.sh`'s `badge_icon`. Draws a colored disc + the profile's initial
  onto a base icon in a headless `NSBitmapImageRep` context (no window — runs
  under plain `osascript`). Reserved-word traps escaped: `|set|`, `|properties|`,
  and `by` avoided. Verifiable headlessly (run it, inspect the PNG); the test
  suite shims `osascript`, so the real render is checked directly, not in-suite.

## Hard-won lessons (do not relearn these)

- **Show Window targets a PID, not a bundle ID** — all instances share
  Claude's bundle ID. The SwiftUI `Focus.show(pid:)` resolves the instance's
  main PID via the engine (`mainpid`/`defaultpid`), then
  `NSRunningApplication runningApplicationWithProcessIdentifier:` +
  `activateWithOptions:`, needing no permissions. macOS 14+ cooperative
  activation can ignore it (other Spaces/displays/fullscreen), so if the app
  isn't frontmost, fall back to System Events `set frontmost of (first
  application process whose unix id is N) to true` — triggers a ONE-TIME
  Automation permission prompt, the only permission in the project. Also
  user-dependent: Desktop & Dock → "switch to a Space with open windows"
  affects the jump.
- **`kill` is a bash builtin** — PATH shims can't intercept it; that's why
  the test suite doesn't exercise quit/force, by design. Keep it that way.
- **Locally generated/built bundles carry no quarantine** — no Gatekeeper
  friction for the maintainer or for wrappers the app generates. DOWNLOADED
  zips/DMGs are quarantined: right-click → Open until Developer ID signing +
  notarization (roadmap).
- **Deep-link logins:** macOS routes `claude://` to one instance; if the
  browser login lands in the wrong window, use the login page's copy-code
  path. Once per profile. Don't attempt LSHandlerRoles hacks.

### Historical (pre-SwiftUI, ≤ v0.6)

These lessons are about the **retired AppleScriptObjC + WebView host** (the
`dashboard.html` / `dashboard.applescript` / `launcher` layer, deleted at the
v0.7.0 SwiftUI cutover). Kept as history so future readers know why the applet
existed and what its constraints were — they no longer apply to the native
SwiftUI `app/`.

- **`osascript` runs scripts on a background thread; AppKit/WebKit require
  the main thread for window creation.** That's why the host was compiled to
  an applet (applets run handlers on the main thread) rather than run as plain
  `osascript` — that failed at runtime.
- **`run` is an AppleScript command name.** `NSApp's run()` is a PARSE error
  (we hit it at char 2326). Pipe-escape reserved words: `|center|()`, etc.
- **JS→native bridge was title polling.** AppleScriptObjC cannot implement
  WKScriptMessageHandler (no subclassing) or completion-handler blocks. The
  page set `document.title = "cp:verb[:arg]"`; a 250ms NSTimer (safe on the
  applet's main thread) polled `theWebView's title()` (KVO-readable, no block
  needed), reset it, dispatched. Native→JS via
  `evaluateJavaScript:completionHandler:(missing value)` (fire-and-forget is
  block-free). Stats pushed on the applet's `on idle` every 2s. (The SwiftUI
  app replaces this entirely with the typed `Process` + `Codable` `EngineClient`
  boundary.)
- **The title bridge could feed back on itself — don't push stats after the
  page's OWN auto-refresh.** An open drill-down kept itself live by having
  `updateStats` set `document.title = "cp:terminals:<slug>"` each tick.
  `checkBridge` (250ms) dispatched that title and used to also call `pushStats`
  afterward — but `pushStats` ran `updateStats`, which re-set the `cp:terminals`
  title, which the next poll caught, re-pushed… so the whole refresh+rebuild
  cycle ran at ~4Hz whenever a terminals panel was open (and only then — that's
  the tell). The fix: in `checkBridge`, only `pushStats` for real user actions,
  i.e. skip it when `rawTitle starts with "cp:terminals"`. (The dashboard also
  deferred DOM updates while the user was actively scrolling, and `render()`
  patched in place unless structure changed.)
- **Replacing an applet's `applet.icns` is NOT enough to brand its Dock
  icon.** osacompile embeds an `Assets.car` and sets `CFBundleIconName`,
  which outranks `CFBundleIconFile` on modern macOS — the Dock kept showing
  the stock AppleScript scroll. `launch_dashboard` had to delete the
  `CFBundleIconName` key and `Assets.car` after compiling (and set a unique
  `CFBundleIdentifier`, since iconservices caches per bundle id).
- **A cached applet could outlive the install path it was compiled for** → blank
  white dashboard. The runtime applet baked the manager's Resources path into
  `loadFileURL:`; if the app moved (`~/Applications` → `/Applications`), the
  reused applet loaded a dead HTML page and WKWebView painted nothing (no
  error). `launch_dashboard` self-healed via `runtime_applet_stale` —
  **exact-match** the baked `resourcesDir` (NOT substring: `/Applications/…` is
  a substring of `/Users/x/Applications/…`, the exact case that bit us) and
  recompile on mismatch. White (not the dark `#1A1915` splash) = document never
  loaded; a JS error would still paint the splash. See
  `docs/postmortems/2026-06-13-white-screen-on-launch.md`.

## Build / test / release

```bash
bash tests/run-tests.sh    # 124 tests; runs on macOS or Linux (mac tools shimmed)
# SwiftUI app (Command Line Tools — no Xcode needed):
cd app && swift build                  # build ProfilesCore + the app shell
cd app && swift run ProfilesCoreTests  # Layer-1 logic tests (executable runner; XCTest doesn't run under CLT)
cd app && swift run ProfilesSnapshotTests  # Layer-2 ImageRenderer render proof
shellcheck -S error src/engine.sh cli/claude-profiles.sh scripts/*.sh
bash scripts/make-icon.sh  # (macOS) regenerate assets/icon.iconset from app-icon.svg via sips
bash scripts/build.sh      # assembles dist/Claude Profiles.app (+ DMG on macOS)
SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=notary \
  bash scripts/sign.sh     # (release-only) sign + notarize + staple the app + DMG
```

CI (`.github/workflows/ci.yml`) runs the first three (tests, shellcheck, build)
on ubuntu-latest; `make-icon.sh` is macOS-only and `sign.sh` is release-only.
Run tests + shellcheck + build before every commit — the suite has already
caught its own author once. New engine features need a test. SwiftUI view
changes are gated by the golden-snapshot harness (`ProfilesSnapshotTests`) plus
maintainer visual/live QA of the running window (the one layer CI can't fully
exercise). The only AppleScript left is `badge-icon.applescript` (the icon
compositor `engine.sh` shells out to); its changes are osacompile parse-checked
on real macOS in `ci-macos.yml` and the rendered PNG verified by hand.

Local install loop during development:
```bash
bash scripts/build.sh && rm -rf ~/Applications/"Claude Profiles.app" \
  && cp -R "dist/Claude Profiles.app" ~/Applications/ && open ~/Applications/"Claude Profiles.app"
```

## Licensing / naming / attribution (decided, don't churn)

Apache-2.0 (canonical text in LICENSE) chosen specifically because §4(d)
makes the NOTICE file's attribution travel with derivative works, plus the
patent grant. NOTICE contains the maintainer's attribution request —
preserve it. The project is UNOFFICIAL; "Claude" is Anthropic's trademark;
the README disclaimer stays. If/when the repo goes public, rename to
"Profiles for Claude" is the agreed safer convention (one line in
src/Info.plist + docs). The maintainer (jyito) wants acknowledgment + contact
if the work is incorporated anywhere — that context matters when editing
NOTICE or README.

## State & immediate next steps

Git history to date: initial release → NOTICE/attribution → Apache-2.0
relicense → consistent-UI dashboard-first → applet/main-thread fix → snappy
actions + Spaces-reliable Show Window → default-instance Quit/Force →
New Profile modal → stable applet identity (Dock icon + sticky Automation
grant) + default Open → **v0.3.0 feature batch**: attribution hardening
(no cross-app metric bleed), per-instance drill-down (terminals table + close,
clean tiers), Throttle, opt-in auto-clean/auto-close settings, button
reactivity + loading screen. Design spec at
`docs/superpowers/specs/2026-06-12-v030-granular-controls-design.md`.

**Awaiting maintainer Mac verification** (the applet/WebView layer the suite
can't exercise — all built + osacompile-clean, none claimed working): Show
Window across Spaces + the one-time Automation prompt; Dock shows the
stacked-windows icon; drill-down round-trip (▾ Terminals populates); terminal
Close hangup reaches a live session; clean-tier clicks; Settings open + change;
Throttle renice. Plus: `tccutil reset AppleEvents local.claude-profiles.dashboard`
if Show Window stays broken with no prompt.

**Icon DONE** (v0.3.0): `assets/app-icon.svg` is the source — a "window stack"
mark (cascading coral/mint/gray app windows on the dark squircle, macOS-grid
margin), trademark-safe, no Anthropic artwork. `scripts/make-icon.sh`
regenerates `assets/icon.iconset` from it with **macOS built-ins only** (`sips`
reads SVG natively — no librsvg); `build.sh` bakes the iconset into the bundle.
Two alternates kept in `assets/icon-candidates/` (fanned deck, profile grid) —
swap `app-icon.svg` and re-run make-icon.sh to change. Reads cleanly at Dock
sizes; collapses to a coral tile at 16px (the layered detail is sub-resolution).

**Deferred to v0.3.1**: launch options (open-minimized isn't clean for
Electron; auto-launch LaunchAgent is persistent system config).

1. **Screenshots/video** (maintainer's Mac): dashboard hero with 2+ profiles
   and live sparklines; ~15s recording ending on a Show Window jump; Dock
   with multiple Claude icons; mounted DMG. Crop to windows (⌘⇧5) — earlier
   captures leaked personal Messages content.
2. **README glow-up** once assets exist: hero image, 3-sentence story,
   demo video, 3-command quickstart, the `--user-data-dir` insight,
   architecture diagram. GitHub READMEs render images + drag-dropped video;
   no CSS/JS survives sanitization; GitHub Pages only after going public.
3. **Push**: `gh repo create jyito/Claude-Profiles --private --source . --push`;
   verify CI green. Put real contact info on the jyito org profile (NOTICE
   points there).
4. **Public-readiness**: name decision, signing/notarization, macOS version
   matrix for the applet, then flip.

Roadmap beyond: SwiftUI dashboard tier (richer UI, needs signing), menu-bar
switcher, per-profile icon badging/tinting, Claude Code parity docs
(CLAUDE_CONFIG_DIR aliases already in cli/).
