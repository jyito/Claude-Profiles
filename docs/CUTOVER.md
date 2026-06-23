# SwiftUI cutover guide

How the manager app changed when it moved from the AppleScriptObjC + WKWebView
host to a native SwiftUI app — and what's left to retire the old host.

The move is split into two phases on purpose:

- **Phase 6a (this PR — non-destructive):** `scripts/build.sh` now ships the
  native SwiftUI `Profiles` binary as the manager, bundling `engine.sh`. Nothing
  is deleted; the old host files stay in `src/` and the change is fully reversible
  via git. A signed `.app` is produced for the maintainer to verify.
- **Phase 6b (later — irreversible):** only **after** the maintainer confirms the
  native app works on their Mac do we delete the WebView host, repoint/retire the
  bash launcher, drop the now-dead CI parse-check, and rewrite `CLAUDE.md`.

The bash **engine** (`src/engine.sh`) is unchanged and stays — it's the shared
data/actions backend for both the old and new front ends.

## New architecture

```
Claude Profiles.app/
  Contents/
    MacOS/Profiles                       # native SwiftUI binary (was: bash `launcher`)
    Resources/
      engine.sh                          # the unchanged bash backend
      badge-icon.applescript             # icon compositor, engine.sh's sibling
      app.icns
    Info.plist                           # CFBundleExecutable = Profiles
```

- **`app/`** — a SwiftPM package built with the **Command Line Tools (no Xcode)**:
  - `ProfilesCore` — pure logic (stats/config/terminal/remote parsing, sorting,
    ptmx leak hysteresis, badge-color math). The seam to the engine is
    `EngineRunning` (`EngineClient` shells out to `engine.sh`; `FixtureEngine`
    serves fixtures for previews/tests).
  - `ProfilesUI` — the SwiftUI views (cards, list, inspector drill-down, sheets,
    menu-bar content), each tagged with `.accessibilityIdentifier(...)`.
  - `Profiles` — the executable (app shell, toolbar, window scene).
  - Tests: `ProfilesCoreTests` (Layer 1 logic) and `ProfilesSnapshotTests`
    (Layer 2 `ImageRenderer` render proofs) — both run as `swift run` executables
    because XCTest doesn't run under CLT.
- **`engine.sh`** — unchanged. The app finds it via `resolveEnginePath()`:
  `SPIKE_ENGINE` (dev override) → `Bundle.main.resourcePath/engine.sh` (the bundled
  copy) → `engine.sh` on PATH. `badge_icon` resolves `badge-icon.applescript` as
  its own sibling (`${BASH_SOURCE%/*}`), so bundling both in Resources works.
- **No applet, no WKWebView, no `document.title` bridge.** The fragile pieces the
  old host needed — main-thread applet compilation, the 250 ms title-polling
  JS↔native bridge, the stale-runtime-applet white-screen self-heal — are gone.
  SwiftUI runs on the main thread natively and calls the engine directly.

### What replaced what

| Old (AppleScriptObjC + WebView) | New (SwiftUI) |
|---|---|
| `src/launcher` (bash executable) | `Profiles` binary (`CFBundleExecutable`) |
| `src/dashboard.html` (the UI) | `app/Sources/ProfilesUI` views |
| `src/dashboard.applescript` (window host + applet) | the SwiftUI `App`/`WindowGroup` scene |
| `document.title` 250 ms bridge + `evaluateJavaScript` push | direct `EngineRunning` calls + `@Observable`/`StatsStore` |
| stay-open applet's `on idle` 2 s stats sweep | the SwiftUI poll clock |
| `NSStatusItem` built in the applet | the SwiftUI menu-bar content |

## Maintainer verification checklist (gates Phase 6b)

Run the signed `.app` on a real Mac and confirm each live behavior the test
layers can't exercise. **All must pass before the Phase 6b deletions.**

Build + run:

```bash
bash scripts/build.sh
SIGN_IDENTITY="Developer ID Application: … (TEAMID)" bash scripts/sign.sh   # no notarization needed to test locally
open "dist/Claude Profiles.app"
```

- [ ] **Launch + render** — the dashboard window opens and shows a card per profile
      + the default instance, populated from the **bundled** `engine.sh` (no
      `SPIKE_ENGINE` set). Live CPU/MEM/terminals tick every ~2 s.
- [ ] **No white screen / no SPIKE_ENGINE leak** — the app finds its engine on its
      own; nothing in the bundle references the dev override.
- [ ] **Show Window** — pressing a running instance's Show Window raises that
      instance's windows (PID-targeted), including across Spaces; the one-time
      Automation prompt appears once and the fallback works.
- [ ] **Menu-bar switcher** — the status item lists the instances and focusing a
      row raises the right PID; **Quit** works; closing the window doesn't quit.
- [ ] **New Profile** — the sheet creates a wrapper with a badged Dock icon; the new
      card appears.
- [ ] **Inspector drill-down** — Details expands; the terminals table populates for a
      running instance; per-row Close hangs up a live terminal; Throttle renices.
- [ ] **Clean tiers** — a stopped instance's clean-tier actions run and refuse while
      running.
- [ ] **Settings** — opens, reads current config, and a change round-trips through
      `getconfig`/`setconfig`.
- [ ] **Remote** — the Remote sheet shows the SSH/Tailscale commands and Copy works;
      the live-dot reflects an actual `screen` session.
- [ ] **Default-instance guardrails hold** — the default card offers Show Window /
      Quit / Force / Remote only; **no Clean, no drill-down/Details, no data-dir
      reads** (the non-negotiable).
- [ ] **Signing** — `codesign --verify --strict "dist/Claude Profiles.app"` passes
      with hardened runtime; the app still spawns `engine.sh` while hardened.
- [ ] **Layer-3 e2e** — `bash scripts/e2e.sh` passes (see `docs/E2E.md`; needs the
      one-time Accessibility grant).

## Phase 6b deletion list (tracked, reviewed step — do NOT do in 6a)

Once the checklist passes, Phase 6b retires the old host:

- **Delete** `src/dashboard.html` (the WebView UI).
- **Delete** `src/dashboard.applescript` (the applet/window host).
- **Retire/trim** `src/launcher` — remove the `launch_dashboard`/applet-compilation
  path. Keep the `--classic` dialog menu + `--action add|remove` CLI flows only if
  still wanted as a headless fallback; otherwise delete `launcher` too.
- **`.github/workflows/ci-macos.yml`** — drop the `dashboard.applescript` line from
  the `osacompile` parse-check (keep `badge-icon.applescript`, still bundled).
- **`CLAUDE.md`** — rewrite the Architecture section to describe `app/`
  (ProfilesCore/ProfilesUI, the `EngineRunning` seam, the snapshot harness); move
  the title-bridge / applet / white-screen "hard-won lessons" to a *Historical
  (pre-SwiftUI)* note; update the Build section for `swift build`/`swift run` + the
  new `build.sh`. **Preserve every non-negotiable** — zero network, never touch
  credentials, default-dir off-limits, precious data dirs, DELETE flow, `${var:?}`
  guards: all still true for the SwiftUI app. Only the "zero build deps / no
  compilation" point relaxes to *"Swift toolchain (CLT) to build, zero RUNTIME
  deps."*
- **`README.md`** — update the architecture blurb + Mermaid diagram (the
  `NSWindow + WKWebView` / `document.title` bridge nodes) to the SwiftUI app.

Nothing above is touched in Phase 6a.
