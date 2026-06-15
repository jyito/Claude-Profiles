# CLAUDE.md — Claude Profiles project context

Read this fully before making changes. It carries the context from the
original development sessions; the reasoning below was paid for in real
debugging on real macOS.

## What this is

Multi-account Claude Desktop for macOS. Each "profile" is a generated native
`.app` wrapper that launches the real Claude.app with its own
`--user-data-dir`, so each account stays permanently signed in and any number
run simultaneously. The user-facing app is a native dashboard window (dark
UI, live per-instance CPU/MEM/PTY/disk, sparklines, Show Window focusing,
cleanup utilities). Status: **v0.3.0 feature-complete, working on the
maintainer's Mac** (applet-layer items pending maintainer verification — see
State section), 99/99 tests, CI configured, private repo target `jyito/Claude-Profiles`,
intended to go public once docs/screenshots/signing are in place.

## Non-negotiables (PRs violating these get declined)

1. **Never touch credentials.** No reading/storing/transmitting tokens,
   passwords, cookies, Keychain. The per-profile data dir IS the credential
   store, managed by Claude Desktop itself. Never script the login UI.
2. **Zero network I/O.** No telemetry, no update checks, nothing. Local-only
   stats (`.profile-activity`, last 50 launches) are the only "analytics."
3. **Zero dependencies.** macOS built-ins only: bash, osascript, osacompile,
   ps, lsof, defaults, du, PlistBuddy. No Homebrew/Node/Python at runtime.
   (Tests use node/python3 but degrade gracefully.)
4. **Never modify Claude.app** — breaks its code signature.
5. **The default data dir (`~/Library/Application Support/Claude`) is
   off-limits.** The default-instance card offers Show Window / Quit / Force
   Quit only — process signals are fine; reads/writes of that dir are not.
   Clean Caches must never appear on the default card.
6. **Profile data dirs are precious.** Destroying one requires the typed
   DELETE flow. Every `rm -rf` uses `${var:?}` guards.
7. **bash 3.2 compatibility.** macOS ships bash 3.2. No `declare -A`,
   `mapfile`, `${var,,}`, or negative substring lengths.

## Architecture (src/)

- **`launcher`** — the manager app's executable (bash). Default behavior:
  compile + open the dashboard applet. `--classic` = dialog menu (also the
  automatic fallback if osacompile fails). `--action add|remove` = dialog
  flows for scripting. Dialog strings go through `esc_msg` (quote + newline
  escaping); all dialogs show the app icon via `dialog_icon`.
- **`engine.sh`** — data/actions backend, shared by both UIs.
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
  Actions: `open quit force clean create remove rebadge purge mainpid defaultpid
  quitdefault forcedefault opendefault terminals closeterm throttle getconfig
  setconfig autotick`. `create`/`rebadge` give each wrapper a distinct Dock icon
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
- **`dashboard.html`** — the entire UI. Dark theme (#1A1915 bg, #21201A
  cards, coral #D85A30 accent, mint #5DCAA5 running state). 30-point rolling
  sparkline history per profile. New Profile = modal over a scrim (Escape /
  scrim-click close, Enter creates). Remove = in-card two-step with typed
  DELETE. `uiLock` pauses live re-render during any form/confirm so the 2s
  tick can't eat input (but NOT during drill-down, so live stats keep ticking
  under an open panel). Cards expand in place (full grid width, one at a time,
  Escape collapses): running → terminals table with per-row close + Throttle;
  stopped → clean tiers. Settings modal drives `getconfig`/`setconfig`.
  Buttons are Title Case (Apple HIG) with hover/press/focus-visible states; a
  startup loading splash shows until the first stats render. Other copy is
  sentence case.
- **`dashboard.applescript`** — window host SOURCE. The launcher substitutes
  `__RESOURCES__` and compiles it with `osacompile -s` into a stay-open applet
  at `~/.claude-instances/.runtime/`, REUSING the compiled applet when the
  source is unchanged (a stable ad-hoc signature keeps the one-time Automation
  grant alive across launches), then `open`s it (re-`open` focuses the existing
  instance). Bridges `terminals`/`getconfig` back to the page via
  `updateTerminals`/`updateConfig`; runs `autotick` every ~16th idle tick.
- **`badge-icon.applescript`** — zero-dep AppleScriptObjC icon compositor called
  by `engine.sh`'s `badge_icon`. Draws a colored disc + the profile's initial
  onto a base icon in a headless `NSBitmapImageRep` context (no window — runs
  under plain `osascript`). Reserved-word traps escaped: `|set|`, `|properties|`,
  and `by` avoided. Verifiable headlessly (run it, inspect the PNG); the test
  suite shims `osascript`, so the real render is checked directly, not in-suite.

## Hard-won lessons (do not relearn these)

- **`osascript` runs scripts on a background thread; AppKit/WebKit require
  the main thread for window creation.** That's why the host is compiled to
  an applet (applets run handlers on the main thread). Do not "simplify"
  back to plain `osascript` execution — it fails at runtime.
- **`run` is an AppleScript command name.** `NSApp's run()` is a PARSE error
  (we hit it at char 2326). Pipe-escape reserved words: `|center|()`, etc.
- **JS→native bridge is title polling.** AppleScriptObjC cannot implement
  WKScriptMessageHandler (no subclassing) or completion-handler blocks. The
  page sets `document.title = "cp:verb[:arg]"`; a 250ms NSTimer (safe on the
  applet's main thread) polls `theWebView's title()` (KVO-readable, no block
  needed), resets it, dispatches. Native→JS via
  `evaluateJavaScript:completionHandler:(missing value)` (fire-and-forget is
  block-free). Stats push on the applet's `on idle` every 2s.
- **The title bridge can feed back on itself — don't push stats after the page's
  OWN auto-refresh.** An open drill-down keeps itself live by having `updateStats`
  set `document.title = "cp:terminals:<slug>"` each tick. `checkBridge` (250ms)
  dispatches that title and used to also call `pushStats` afterward — but
  `pushStats` runs `updateStats`, which re-sets the `cp:terminals` title, which
  the next poll catches, re-pushes… so the whole refresh+rebuild cycle ran at
  ~4Hz whenever a terminals panel was open (and only then — that's the tell). The
  fix: in `checkBridge`, only `pushStats` for real user actions, i.e. skip it when
  `rawTitle starts with "cp:terminals"`. Any new self-arming `cp:` verb needs the
  same exclusion. (The dashboard also defers DOM updates while the user is
  actively scrolling, and `render()` patches in place unless structure changed —
  see the in-place-patch note in dashboard.html.)
- **Show Window targets a PID, not a bundle ID** — all instances share
  Claude's bundle ID. `NSRunningApplication
  runningApplicationWithProcessIdentifier:` + `activateWithOptions:3`,
  needing no permissions. macOS 14+ cooperative activation can ignore it
  (other Spaces/displays/fullscreen), so after 0.3s, if `isActive` is false,
  fall back to System Events `set frontmost of (first application process
  whose unix id is N) to true` — triggers a ONE-TIME Automation permission
  prompt, the only permission in the project. Also user-dependent: Desktop &
  Dock → "switch to a Space with open windows" affects the jump.
- **Replacing an applet's `applet.icns` is NOT enough to brand its Dock
  icon.** osacompile embeds an `Assets.car` and sets `CFBundleIconName`,
  which outranks `CFBundleIconFile` on modern macOS — the Dock keeps showing
  the stock AppleScript scroll. `launch_dashboard` must delete the
  `CFBundleIconName` key and `Assets.car` after compiling (and sets a unique
  `CFBundleIdentifier`, since iconservices caches per bundle id). Don't
  "clean up" that block.
- **`kill` is a bash builtin** — PATH shims can't intercept it; that's why
  the test suite doesn't exercise quit/force, by design. Keep it that way.
- **A cached applet can outlive the install path it was compiled for** → blank
  white dashboard. The runtime applet bakes the manager's Resources path into
  `loadFileURL:`; if the app moves (`~/Applications` → `/Applications`), the
  reused applet loads a dead `dashboard.html` and WKWebView paints nothing (no
  error). `launch_dashboard` self-heals via `runtime_applet_stale` —
  **exact-match** the baked `resourcesDir` (NOT substring: `/Applications/…` is
  a substring of `/Users/x/Applications/…`, the exact case that bit us) and
  recompile on mismatch. Recovery for users: `rm -rf ~/.claude-instances/.runtime`.
  White (not the dark `#1A1915` splash) = document never loaded; a JS error
  would still paint the splash. See `docs/postmortems/2026-06-13-white-screen-on-launch.md`.
- **Locally generated/built bundles carry no quarantine** — no Gatekeeper
  friction for the maintainer or for wrappers the app generates. DOWNLOADED
  zips/DMGs are quarantined: right-click → Open until Developer ID signing +
  notarization (roadmap).
- **Deep-link logins:** macOS routes `claude://` to one instance; if the
  browser login lands in the wrong window, use the login page's copy-code
  path. Once per profile. Don't attempt LSHandlerRoles hacks.

## Build / test / release

```bash
bash tests/run-tests.sh    # 99 tests; runs on macOS or Linux (mac tools shimmed)
shellcheck -S error src/launcher src/engine.sh cli/claude-profiles.sh scripts/*.sh
bash scripts/make-icon.sh  # (macOS) regenerate assets/icon.iconset from app-icon.svg via sips
bash scripts/build.sh      # assembles dist/Claude Profiles.app (+ DMG on macOS)
SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=notary \
  bash scripts/sign.sh     # (release-only) sign + notarize + staple the app + DMG
```

CI (`.github/workflows/ci.yml`) runs the first three (tests, shellcheck, build)
on ubuntu-latest; `make-icon.sh` is macOS-only and `sign.sh` is release-only.
Run tests + shellcheck + build before every commit — the suite has already
caught its own author once. New engine features need a test. Changes to
`dashboard.applescript` MUST be tested on real macOS (the one layer the
suite can't run) and PRs should state which macOS versions.

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
