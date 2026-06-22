# SwiftUI Dashboard — Phase 4 (Modals) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Logic tasks TDD (`swift run ProfilesCoreTests`); sheet views via golden snapshots + controller visual-QA against `docs/superpowers/specs/2026-06-22-swiftui-dashboard-design.md`.

**Goal:** The four `.sheet` modals — New Profile (live identity-disc preview), Settings (native `Form` + the three auto-rule `Picker`s wired to `getconfig`/`setconfig`), Cleanup (Quit All / Clear Caches / Emergency Stop), and Remote access (SF-Mono SSH blocks + a `CIQRCodeGenerator` QR + Copy → `pbcopy`) — wired to the toolbar + the card Remote button.

**Architecture:** Extend the seam with typed config + remote info + create (all decode engine output). New `ProfilesUI/Sheets/` views are pure (take fixtures + `onSubmit`/`onAction` closures); the scene owns `@State` sheet enums and performs engine calls. Reuse `Theme`, `PillButtonStyle`, `BadgeDisc`, the snapshot harness, and the `snapshotMode` flag.

**Tech Stack:** SwiftUI `.sheet`/`Form`/`Picker`/`GroupBox`, CoreImage `CIQRCodeGenerator`. ProfilesCore (Codable). CLT build, no Xcode.

---

### Task 1: Typed config + create + badge-preview helpers (TDD)

**Files:** Create `app/Sources/ProfilesCore/ProfileConfig.swift`, `app/Sources/ProfilesCore/BadgePreview.swift`; Modify the seam (`EngineRunning`/`EngineClient`/`FixtureEngine`, `StatsStore`); Create `app/Sources/ProfilesCoreTests/ConfigTests.swift`, `BadgePreviewTests.swift`; register.

**First read `src/engine.sh`** for: `cmd_getconfig` (JSON shape), `cmd_setconfig` (keys/values), `cmd_create` (return format, e.g. `ok <slug>` / `err <msg>`), the slug derivation in `create`, and `badge_color_for` (`cksum(slug) % 6`) + the palette order.

- [ ] **Step 1 (config, TDD):** `ProfileConfig: Codable { autoCleanThresholdMB:Int; autoCloseIdleMin:Int; autoRestartLeakAt:Int }`. Test: decode the `getconfig` JSON. Seam: `func getConfig() async throws -> ProfileConfig` (decode `getconfig`), `func setConfig(_ key: String, _ value: Int) async throws` (→ `run(["setconfig", key, String(value)])`, which already throws on `err`). `StatsStore.loadConfig()` + a published `config`. FixtureEngine returns a canned config + records setConfig. Test the store path.
- [ ] **Step 2 (create, TDD):** seam `func create(_ name: String) async throws -> String` — runs `["create", name]`, parses `ok <slug>` → returns slug, throws `actionFailed` on `err …`. (Note: `create` prints `ok <slug>` to stdout — capture it specifically; don't route through the generic `run` which would treat any non-`err` stdout as success but discard the slug.) Test with a stub engine printing `ok work2`.
- [ ] **Step 3 (badge preview, TDD):** `BadgePreview`: `func slugify(_ name: String) -> String` (mirror engine `create`'s lowercase-alphanumeric extraction) and `func badgeColorIndex(forSlug:) -> Int` (port engine `badge_color_for` = POSIX `cksum` of the slug `% 6`; **port the exact POSIX cksum CRC so the preview matches the real assignment** — if the cksum port proves impractical, use a documented approximation and note it) + `func initial(forName:) -> String` ("Claude "-stripped, first letter, uppercased). Test slugify + initial against known cases; test the color index is deterministic.
- [ ] **Step 4:** Register all suites; all green (count grows ~+6). Commit `feat(core): ProfileConfig + create + badge-preview seam`.

### Task 2: New Profile sheet (snapshot)

**Files:** Create `app/Sources/ProfilesUI/Sheets/NewProfileSheet.swift`; wire the toolbar; register snapshot.

- [ ] **Step 1** — `NewProfileSheet(onCreate:(String)->Void, onCancel:()->Void)`: `.title3` "New profile" heading + a help line + a row with a **live `BadgeDisc` preview** (color from `BadgePreview.badgeColorIndex(forSlug: slugify(typed))`, initial from the typed name) beside a `TextField` (coral focus ring) + a caption ("'Marketing' will get a teal badge with M"), and Cancel + a coral "Create Profile" (Enter submits, Esc cancels, disabled when empty). Pure view; the live preview updates as `@State text` changes. Snapshot uses a fixed typed value via a `snapshotText` param.
- [ ] **Step 2** — Wire the toolbar's New Profile button (and ⌘N) to present this sheet; `onCreate` → `Task { try? await store.engineCreate(name); await store.refreshOnce() }`.
- [ ] **Step 3** — Snapshot `sheet-newprofile` (fixed text "Marketing"). Record + verify.
- [ ] **Step 4** — Commit `feat(ui): New Profile sheet + live badge preview (+ golden)`.

### Task 3: Settings sheet (snapshot)

**Files:** Create `app/Sources/ProfilesUI/Sheets/SettingsSheet.swift`; wire toolbar (⌘,); register snapshot.

- [ ] **Step 1** — `SettingsSheet(config:ProfileConfig, onChange:(String,Int)->Void)`: a native `Form` with three `Picker`s — **Auto-Clean stopped profiles** (Off / 500 MB / 1 GB / 2 GB / 5 GB → `autoCleanThresholdMB`), **Auto-Close idle terminals** (Off / 30 min / 1 h / 2 h / 4 h → `autoCloseIdleMin`, amber ⚠ note "long silent tasks look idle"), **Auto-Restart on handle leak** (Off / 150 / 250 / 350 → `autoRestartLeakAt`, amber ⚠ note "the default instance is never auto-restarted"). Each change calls `onChange(key, value)`. Close button. Native `Form`/`LabeledContent` styling (not hand-spaced).
- [ ] **Step 2** — Wire the Settings toolbar button to present it, loading `store.config` first; `onChange` → `store.setConfig`.
- [ ] **Step 3** — Snapshot `sheet-settings` (a fixture config). Record + verify. (Note: native `Form`/`Picker` may not render under `ImageRenderer` — if so, use the established hand-built/`PillButtonStyle` stand-in pattern for the snapshot while keeping the real `Form` in the live app, and snapshot the row content.)
- [ ] **Step 4** — Commit `feat(ui): Settings sheet wired to getconfig/setconfig (+ golden)`.

### Task 4: Cleanup sheet (snapshot)

**Files:** Create `app/Sources/ProfilesUI/Sheets/CleanupSheet.swift`; wire toolbar; register snapshot.

- [ ] **Step 1** — `CleanupSheet(onAction:(CleanupAction)->Void)` with `enum CleanupAction { case quitAll, cleanAll, emergencyStop }`: three bordered rows — "Quit All Profiles" (sub: "default Claude keeps running"), "Clear Caches on Stopped" (sub: "frees disk; running skipped"), and "Emergency Stop" (desaturated-red, **2-step arm→confirm**, sub: "force-quits all instances + default"). Maps to `quitall` / `cleanall` / `killswitch`.
- [ ] **Step 2** — Wire the Cleanup toolbar button; `onAction` → `store.perform([verb])`.
- [ ] **Step 3** — Snapshots `sheet-cleanup`, `sheet-cleanup-armed` (emergency armed). Record + verify.
- [ ] **Step 4** — Commit `feat(ui): Cleanup sheet (+ goldens)`.

### Task 5: RemoteInfo seam + QR helper (TDD)

**Files:** Create `app/Sources/ProfilesCore/RemoteInfo.swift`; Modify seam; Create `app/Sources/ProfilesUI/QRCode.swift`; Create `app/Sources/ProfilesCoreTests/RemoteInfoTests.swift`; register.

**First read `src/engine.sh` `cmd_remoteinfo`** for the JSON shape.

- [ ] **Step 1 (TDD)** — `RemoteInfo: Codable { slug:String; session:String; user:String; host:String; tailscaleIp:String; alreadyRunning:Bool }` (+ optional `error`). Test decode. Seam: `func remoteInfo(_ slug: String) async throws -> RemoteInfo` (decode `remoteinfo <slug>`); `func copy(_ text: String) async throws` (→ `run(["copy", text])`). FixtureEngine returns canned info. Test.
- [ ] **Step 2** — `QRCode.image(for string: String) -> NSImage?`: CoreImage `CIQRCodeGenerator` (errorCorrection "L") → `CIContext.createCGImage` → `NSImage`, nearest-neighbour scaled. Deterministic for a fixed input.
- [ ] **Step 3** — Register suites; green. Commit `feat(core): RemoteInfo seam + QR generator`.

### Task 6: Remote sheet (snapshot)

**Files:** Create `app/Sources/ProfilesUI/Sheets/RemoteSheet.swift`; wire the card Remote button; register snapshot.

- [ ] **Step 1** — `RemoteSheet(info:RemoteInfo, onCopy:(String)->Void, onClose:()->Void)`: title "Remote access — {name}" + a mint live-dot when `alreadyRunning`; SF-Mono SSH command blocks — local (`ssh {user}@{host} -t "screen -r {session}"`) and, when `tailscaleIp` non-empty, any-network (`ssh {user}@{tailscaleIp} …`) — each with a trailing "Copy" `PillButton` (`onCopy(cmd)`); a `QRCode.image(for:)` of the local attach command rendered in an `Image`; a collapsible "Show iPad / Tailscale setup" with numbered steps; a Close button. Error path: if `info.error` set, show it.
- [ ] **Step 2** — Wire the card's existing Remote button to load `remoteInfo(slug)` and present this sheet.
- [ ] **Step 3** — Snapshot `sheet-remote` (fixture RemoteInfo with a fixed tailscaleIp so the QR is deterministic). Record + verify. Controller QA the QR renders + scans-plausibly.
- [ ] **Step 4** — Commit `feat(ui): Remote sheet + QR + copy (+ golden)`.

### Task 7: Full verify + visual QA + CI + merge

- [ ] **Step 1** — `swift build -c release`; `swift run ProfilesCoreTests` (all green); `swift run ProfilesSnapshotTests` (all goldens). Live run: New Profile creates a wrapper, Settings round-trips a value, Cleanup actions fire, Remote opens with real SSH/QR (controller QA against real engine).
- [ ] **Step 2** — Controller opens every new sheet golden vs the mockup; fix drift.
- [ ] **Step 3** — Open the Phase 4 PR; CI green; merge.

---

## Self-review notes (author)
- **Spec coverage:** New Profile + live preview (T2), Settings + getconfig/setconfig (T1, T3), Cleanup incl. emergency 2-step (T4), Remote + SSH + QR + copy (T5, T6). Menu-bar/Show-Window/list-view/states are Phase 5.
- **Type consistency:** `ProfileConfig`/`RemoteInfo` decode in the seam (T1, T5) → store → sheets. `CleanupAction` enum (T4). `BadgePreview` (T1) feeds the New Profile preview (T2). All actions route through the Phase-3 `run([args])`/`perform`, inheriting the error-token throwing.
- **Safety:** Emergency Stop is 2-step; create/setconfig surface engine `err` tokens (Phase-3 seam). Engine verbs already have bash tests per CLAUDE.md.
- **Snapshot caveat:** native `Form`/`Picker`/`TextField` may not render under `ImageRenderer` — reuse Phase 2/3's hand-built stand-in pattern for goldens while the live app keeps native controls.
