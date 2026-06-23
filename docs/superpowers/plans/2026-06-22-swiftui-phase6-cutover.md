# SwiftUI Dashboard — Phase 6 (e2e + Cutover) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. This phase touches the production build + retires the old host, so it is split: **6a is non-destructive** (build the SwiftUI app, bundle engine.sh, e2e scaffold, docs — NO deletions, NO CLAUDE.md rewrite) and produces a **signed app for maintainer verification**; **6b is the irreversible cutover** (delete the WebView host, repoint the launcher, rewrite CLAUDE.md) and runs **only after the maintainer confirms the native app works on their Mac**.

**Goal:** Make the native SwiftUI app the shippable "Claude Profiles.app" (built + signed from `scripts/build.sh`/`sign.sh`, self-contained with bundled `engine.sh`), stand up a maintainer-runnable Layer-3 e2e smoke harness, and — after maintainer sign-off — retire the AppleScriptObjC+WebView host.

**Architecture:** `build.sh` assembles the bundle with the Swift `Profiles` binary as `CFBundleExecutable` and `engine.sh`+`badge-icon.applescript`+`app.icns` in Resources; the app's existing `resolveEnginePath()` already falls back to `Bundle.main.resourcePath/engine.sh`, so the bundled app is self-contained (no `SPIKE_ENGINE`). `sign.sh` signs it (Developer ID + hardened runtime). e2e is an `AXUIElement` driver vs a stubbed engine — a maintainer gate, NOT hosted CI (SIP blocks TCC).

---

## PHASE 6a — non-destructive (autonomous)

### Task 1: Bundle self-containment (verify + adjust)

**Files:** read `app/Sources/Profiles/EnginePath.swift`, `src/engine.sh` (`badge_icon`/`SCRIPT_DIR` resolution).

- [ ] **Step 1** — Confirm `resolveEnginePath()` returns `Bundle.main.resourcePath + "/engine.sh"` when `SPIKE_ENGINE` is unset, so a launched `.app` finds the bundled engine. Confirm `engine.sh`'s `badge_icon` resolves `badge-icon.applescript` relative to engine.sh's own dir (so bundling both in Resources works). If either is wrong, fix minimally (e.g. engine resolves its sibling via `${BASH_SOURCE%/*}`). No behavior change to `swift run` dev mode.
- [ ] **Step 2** — Commit `fix(app): self-contained bundled engine path` (only if a change was needed; else skip).

### Task 2: Fold the SwiftUI build into `scripts/build.sh` (keep old files)

**Files:** Modify `scripts/build.sh`, `src/Info.plist`.

- [ ] **Step 1** — In `build.sh`, replace the bundle assembly so it: runs `(cd app && swift build -c release)`, copies `app/.build/release/Profiles` → `Contents/MacOS/Profiles`, copies `src/engine.sh` + `src/badge-icon.applescript` → Resources, keeps the `app.icns` iconset step, and writes `Info.plist` with `CFBundleExecutable=Profiles`. **Stop copying `dashboard.html`/`dashboard.applescript`** (the SwiftUI app doesn't use them; the source files stay in `src/` for now — 6b deletes them). Do NOT add signing here (signing stays in `sign.sh`). Keep the zip/DMG packaging.
- [ ] **Step 2** — Update `src/Info.plist`: `CFBundleExecutable` → `Profiles`; ensure `LSMinimumSystemVersion` 14.0; remove `LSUIElement` if present (the SwiftUI app is a regular windowed app); keep the identifier + bump nothing (version bump happens at release).
- [ ] **Step 3** — Run `bash scripts/build.sh`; confirm it produces `dist/Claude Profiles.app` with `Contents/MacOS/Profiles` (a Mach-O binary) + `Resources/engine.sh`. (CI's `ci-macos.yml` build step runs this — it must succeed unsigned.)
- [ ] **Step 4** — Commit `build: assemble the native SwiftUI app (Profiles binary + bundled engine)`.

### Task 3: Confirm `sign.sh` signs the SwiftUI app

**Files:** read/adjust `scripts/sign.sh`.

- [ ] **Step 1** — Confirm `sign.sh` codesigns `dist/Claude Profiles.app` with `--options runtime` (hardened) + `--timestamp` + the Developer ID, and that no special entitlements are needed (the spike proved a non-sandboxed hardened app spawns `engine.sh` fine). If `sign.sh` references old files or needs an entitlements file, adjust minimally. (Do NOT run notarization here — that's release-time.)
- [ ] **Step 2** — Commit `sign: confirm hardened-runtime signing of the native app` (only if a change was needed).

### Task 4: Layer-3 e2e smoke harness (maintainer gate)

**Files:** Create `scripts/e2e/axdrive.swift`, `scripts/e2e/engine-stub.sh`, `scripts/e2e/flows.sh`, `scripts/e2e.sh`, `docs/E2E.md`.

Minimal but real — the testing strategy flags e2e as the flakiest layer (maintainer-runnable, not hosted CI).

- [ ] **Step 1** — `axdrive.swift`: a ~80-line `AXUIElement` driver compiled with `swiftc` (no Xcode) that finds elements by `AXIdentifier` (DFS over the AX tree), can `kAXPressAction` and read `AXValue`/`AXDescription`. `engine-stub.sh`: a fixture engine (`stats` → fixed JSON, `create`/`mainpid`/etc. → canned) so no real Claude is needed.
- [ ] **Step 2** — `flows.sh` + `scripts/e2e.sh`: launch the built app with `SPIKE_ENGINE` pointed at the stub, then drive 2–3 smoke flows by accessibilityIdentifier (launch→first-render shows cards; New Profile sheet opens; the grid is present) and assert via the AX tree / stub side-effects. Exit non-zero on failure. `docs/E2E.md`: how to run it, the one-time Accessibility TCC grant for the driver, and why it's a maintainer gate (SIP blocks hosted CI).
- [ ] **Step 3** — Compile `axdrive.swift` (`swiftc`) to confirm it builds; do NOT run the live flows (needs the GUI + TCC — maintainer runs it). Commit `test(e2e): AXUIElement smoke harness (maintainer gate)`.

### Task 5: Additive cutover docs

**Files:** Create `docs/CUTOVER.md`.

- [ ] **Step 1** — `docs/CUTOVER.md`: the new architecture (SwiftUI app + engine.sh, no applet/WebView), the maintainer verification checklist (the live behaviors), and the 6b deletion list (so it's a tracked, reviewed step). Do NOT edit CLAUDE.md yet (that's 6b).
- [ ] **Step 2** — Commit `docs: cutover guide + maintainer verification checklist`.

### Task 6 (controller, not the implementer): build + sign + hand off

- [ ] **Step 1** — Controller runs `bash scripts/build.sh`, signs with the Developer ID + hardened runtime, runs `codesign --verify --strict`, and confirms the bundle launches + finds the bundled `engine.sh` (no `SPIKE_ENGINE`).
- [ ] **Step 2** — Open the Phase 6a PR; CI green; merge.
- [ ] **Step 3** — Hand the maintainer the signed `.app` + the `docs/CUTOVER.md` verification checklist. **STOP. Wait for sign-off before 6b.**

---

## PHASE 6b — irreversible cutover (ONLY after maintainer verifies the live app)

### Task 7: Retire the WebView host + repoint + docs

**Files:** Delete `src/dashboard.html`, `src/dashboard.applescript`; trim `src/launcher` (remove `launch_dashboard`/applet path — keep `--classic`/CLI fallbacks only if still wanted, else retire `launcher` too); Modify `.github/workflows/ci-macos.yml` (drop the `dashboard.applescript` osacompile parse-check); Modify `CLAUDE.md` (Architecture + Build sections); Modify `README.md` if it references the WebView host.

- [ ] **Step 1** — Delete the WebView host files; remove the now-dead applet-compilation path; drop the osacompile parse-check step for `dashboard.applescript` from CI.
- [ ] **Step 2** — Update `CLAUDE.md`: the Architecture section now describes the SwiftUI app (`app/`, ProfilesCore/ProfilesUI, the engine seam, the snapshot harness) replacing `dashboard.html`/`dashboard.applescript`; the title-bridge/applet/white-screen "hard-won lessons" move to a "Historical (pre-SwiftUI)" note; the Build section documents `app/` (`swift build`/`swift run` runners) + the new `build.sh`. **Preserve every non-negotiable** (zero network, never touch credentials, default-dir off-limits, precious data dirs, etc. — all still true for the SwiftUI app); only the "no compilation / zero build deps" point is relaxed to "Swift toolchain (CLT) to build, zero RUNTIME deps."
- [ ] **Step 3** — Full suite (`tests/run-tests.sh` + `swift run` runners), `build.sh`, CI green. Open the Phase 6b PR; merge. **Cutover complete.**

---

## Self-review notes (author)
- **Spec coverage:** build integration + bundled engine (T1–T3), e2e harness (T4), cutover docs (T5), the irreversible retire/repoint/CLAUDE.md (T7). The "ship behind the existing manager until parity verified, then delete" spec instruction is honored by the 6a/6b split.
- **Non-destructive guarantee (6a):** no source deletions, no CLAUDE.md rewrite; the only `build.sh` change (stop bundling the HTML/applet) is reversible via git, and released versions are unaffected. The signed app is produced for verification before anything is destroyed.
- **Honest boundary:** the live focus/menu-bar/Show-Window behaviors + the e2e flows need the maintainer's Mac + the Automation/Accessibility prompts — verified by the maintainer in Task 6 Step 3, gating 6b.
