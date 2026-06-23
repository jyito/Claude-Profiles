import SwiftUI
import ProfilesCore
import ProfilesUI

/// The registry of golden-PNG cases. Each Phase-2 task appends its view's cases
/// here. Kept separate from the harness so view tasks touch only this list.
@MainActor
enum SnapshotCases {
    static func all() -> [SnapshotCase] {
        var cases: [SnapshotCase] = []

        // Task 3 — BadgeDisc + StatusDot
        cases.append(SnapshotCase("badge-business", size: CGSize(width: 60, height: 60)) {
            BadgeDisc(name: "Business", colorHex: "#3B7DD8", slug: "business", size: 34)
        })
        cases.append(SnapshotCase("badge-default-lock", size: CGSize(width: 60, height: 60)) {
            BadgeDisc(name: "Claude (default)", colorHex: "#6E6A62", slug: "", size: 34, isDefault: true)
        })
        cases.append(SnapshotCase("dot-running", size: CGSize(width: 40, height: 40)) {
            StatusDot(running: true, size: 8)
        })
        cases.append(SnapshotCase("dot-stopped", size: CGSize(width: 40, height: 40)) {
            StatusDot(running: false, size: 8)
        })

        // Task 4 — Sparkline (Swift Charts)
        cases.append(SnapshotCase("spark-cpu", size: CGSize(width: 140, height: 44)) {
            Sparkline(values: Fixtures.cpuSeries, tint: Theme.cpuLine)
                .padding(.horizontal, 6)
        })
        cases.append(SnapshotCase("spark-mem", size: CGSize(width: 140, height: 44)) {
            Sparkline(values: Fixtures.memSeries, tint: Theme.memLine)
                .padding(.horizontal, 6)
        })
        cases.append(SnapshotCase("spark-ghost", size: CGSize(width: 140, height: 44)) {
            Sparkline.ghosted(Fixtures.cpuSeries)
                .padding(.horizontal, 6)
        })

        // Task 5 — running ProfileCard (calm) + warning gauge
        cases.append(SnapshotCase("card-running-business", size: CGSize(width: 340, height: 300)) {
            ProfileCardView(stat: Fixtures.business, cpu: Fixtures.cpuSeries,
                            mem: Fixtures.memSeries, state: .calm, selected: false)
                .padding(Theme.Space.lg)
        })
        cases.append(SnapshotCase("card-running-research-warning", size: CGSize(width: 340, height: 300)) {
            // Unselected so the amber *severity* border shows (the coral selection
            // ring would otherwise mask it — that path is covered by window-full).
            ProfileCardView(stat: Fixtures.research, cpu: Fixtures.cpuSeriesHot,
                            mem: Fixtures.memSeriesHot, state: .warning(climbing: true), selected: false)
                .padding(Theme.Space.lg)
        })

        // Task 6 — stopped + default ProfileCard variants
        cases.append(SnapshotCase("card-stopped-clientx", size: CGSize(width: 340, height: 250)) {
            ProfileCardView(stat: Fixtures.clientX, cpu: Fixtures.cpuSeries,
                            mem: Fixtures.memSeries, state: .calm, selected: false)
                .padding(Theme.Space.lg)
        })
        cases.append(SnapshotCase("card-default", size: CGSize(width: 340, height: 280)) {
            ProfileCardView(stat: Fixtures.defaultInstance, cpu: Fixtures.cpuSeries,
                            mem: Fixtures.memSeries, state: .calm, selected: false)
                .padding(Theme.Space.lg)
        })
        // The quit default: stopped status line + protected note + an Open / Remote
        // row (the relaunch affordance the bug suppressed). Restricted-default
        // contract holds — no metrics, no Details, no clean tiers.
        cases.append(SnapshotCase("card-default-stopped", size: CGSize(width: 340, height: 200)) {
            ProfileCardView(stat: Fixtures.defaultStopped, cpu: Fixtures.cpuSeries,
                            mem: Fixtures.memSeries, state: .calm, selected: false)
                .padding(Theme.Space.lg)
        })

        // Task 7 — KPI instrument strip
        cases.append(SnapshotCase("kpi-strip", size: CGSize(width: 820, height: 110)) {
            KPIStripView(profiles: Fixtures.all)
                .padding(Theme.Space.lg)
        })

        // Task 8 — sidebar. The REAL hand-built `SidebarView` (it renders headlessly
        // now — no native `List`), so the golden verifies what ships. A constant
        // selection drives the highlight.
        cases.append(SnapshotCase("sidebar", size: CGSize(width: 240, height: 320)) {
            SidebarView(profiles: Fixtures.all, selection: .constant(nil))
                .background(Theme.canvas)
        })

        // Task 9 — full window (sidebar + KPI strip + card grid), looser tolerance.
        let cards: [CardModel] = [
            CardModel(stat: Fixtures.defaultInstance, cpu: Fixtures.cpuSeries,
                      mem: Fixtures.memSeries, state: .calm),
            CardModel(stat: Fixtures.business, cpu: Fixtures.cpuSeries,
                      mem: Fixtures.memSeries, state: .calm),
            CardModel(stat: Fixtures.research, cpu: Fixtures.cpuSeriesHot,
                      mem: Fixtures.memSeriesHot, state: .warning(climbing: true)),
            CardModel(stat: Fixtures.clientX, cpu: Fixtures.cpuSeries,
                      mem: Fixtures.memSeries, state: .calm),
        ]
        cases.append(SnapshotCase("window-full", size: CGSize(width: 1080, height: 720), tolerance: 0.01) {
            HStack(spacing: 0) {
                SidebarView(profiles: Fixtures.all, selection: .constant(nil))
                    .background(Theme.canvas)
                    .frame(width: 240, height: 720)
                DashboardContent(profiles: Fixtures.all, cards: cards, selection: "research", scrolls: false)
                    .frame(width: 840, height: 720)
            }
        })

        // ── Phase 3: Inspector drill-down ──────────────────────────────────────

        // Task 3 — inspector header (the identity row over the body's eyebrow).
        // Uses the default instance with no terminals so only the header + the
        // "No terminals open" line render — a clean, header-focused proof.
        cases.append(SnapshotCase("inspector-header", size: CGSize(width: 340, height: 130)) {
            InspectorView(stat: Fixtures.defaultInstance, terminals: [], state: .calm, onAction: { _ in })
        })

        // Task 4 — terminals table (3 rows, the middle one armed → "Confirm")
        cases.append(SnapshotCase("inspector-terminals", size: CGSize(width: 340, height: 180)) {
            TerminalsTable(terminals: Fixtures.terminals, snapshotArmedDev: "/dev/ttys007") { _ in }
                .padding(Theme.Space.lg)
        })

        // Task 5 — leak-restart block (amber, warning) — resting + armed
        cases.append(SnapshotCase("inspector-leakblock-warning", size: CGSize(width: 340, height: 180)) {
            LeakBlock(stat: Fixtures.research, state: .warning(climbing: true)) { }
                .padding(Theme.Space.lg)
        })
        cases.append(SnapshotCase("inspector-leakblock-armed", size: CGSize(width: 340, height: 220)) {
            LeakBlock(stat: Fixtures.research, state: .warning(climbing: true), snapshotArmed: true) { }
                .padding(Theme.Space.lg)
        })

        // Task 6 — clean tiers (stopped fixture: 920 MB on disk)
        cases.append(SnapshotCase("inspector-cleantiers", size: CGSize(width: 340, height: 220)) {
            CleanTiers(disk: Fixtures.clientX.disk) { _ in }
                .padding(Theme.Space.lg)
        })

        // Task 7 — badge picker (clientX is pink → index 4 ringed) + armed remove
        cases.append(SnapshotCase("inspector-badgepicker", size: CGSize(width: 340, height: 90)) {
            BadgePicker(currentHex: Fixtures.clientX.color, slug: Fixtures.clientX.slug) { _ in }
                .padding(Theme.Space.lg)
        })
        cases.append(SnapshotCase("inspector-remove-armed", size: CGSize(width: 340, height: 200)) {
            RemoveProfile(name: Fixtures.clientX.name, snapshotExpanded: true) { }
                .padding(Theme.Space.lg)
        })

        // Task 8 — assembled inspector bodies by state (looser tolerance: tall composites)
        cases.append(SnapshotCase("inspector-running-full", size: CGSize(width: 360, height: 540), tolerance: 0.015) {
            InspectorView(stat: Fixtures.business, terminals: Fixtures.terminals,
                          state: .warning(climbing: false)) { _ in }
        })
        cases.append(SnapshotCase("inspector-stopped-full", size: CGSize(width: 360, height: 480), tolerance: 0.015) {
            InspectorView(stat: Fixtures.clientX, terminals: [], state: .calm) { _ in }
        })
        cases.append(SnapshotCase("inspector-default", size: CGSize(width: 360, height: 320), tolerance: 0.015) {
            // Restricted default: terminals ONLY — structurally no clean/badge/remove.
            InspectorView(stat: Fixtures.defaultInstance, terminals: Fixtures.terminals,
                          state: .calm) { _ in }
        })

        // Task 9 — maximized master-detail page (the `.inspector` replacement). A
        // running profile: header (badge + name + status) over the consolidated action
        // bar (Show Window · Remote · Throttle CPU · Restart · ⋯ overflow glyph) over
        // the three hero trend charts (CPU coral / MEMORY teal / HANDLE POOL amber with
        // a dashed ceiling rule + a "▲ climbing — restart soon" verdict) and the stat
        // strip (procs · terminals · disk · opened · last · remote) over the shared
        // `InstanceSections` (terminals + leak block — Throttle moved up to the action
        // bar). Looser tolerance: tall composite. snapshotMode renders the bare VStack
        // (no ScrollView) and the overflow glyph (a `Menu` paints empty headless).
        cases.append(SnapshotCase("profile-detail", size: CGSize(width: 720, height: 820), tolerance: 0.015) {
            ProfileDetailView(
                stat: Fixtures.research, cpu: Fixtures.cpuSeriesHot, mem: Fixtures.memSeriesHot,
                ptmx: Fixtures.ptmxSeriesHot,
                state: .warning(climbing: true), terminals: Fixtures.terminals,
                onAction: { _ in })
        })

        // ── Phase 4: Sheets ────────────────────────────────────────────────────

        // Task 2 — New Profile sheet with a fixed typed name. "Marketing" → cksum
        // % 6 == 2 → amber badge with M (the live preview the user sees as they type).
        cases.append(SnapshotCase("sheet-newprofile", size: CGSize(width: 420, height: 280)) {
            NewProfileSheet(snapshotText: "Marketing", onCreate: { _ in }, onCancel: {})
        })

        // Task 3 — Settings sheet. A fixture config with each rule on a non-Off
        // option (1 GB / 1 hour / 250) so the stand-in pills read distinctly; the
        // two footgun rules show their amber ⚠ notes.
        cases.append(SnapshotCase("sheet-settings", size: CGSize(width: 460, height: 470)) {
            SettingsSheet(
                config: ProfileConfig(autoCleanThresholdMB: 1024, autoCloseIdleMin: 60, autoRestartLeakAt: 250),
                onChange: { _, _ in }, onClose: {})
        })

        // Task 4 — Cleanup sheet, resting + Emergency armed (the 2-step confirm state).
        cases.append(SnapshotCase("sheet-cleanup", size: CGSize(width: 440, height: 420)) {
            CleanupSheet(onAction: { _ in }, onClose: {})
        })
        cases.append(SnapshotCase("sheet-cleanup-armed", size: CGSize(width: 440, height: 420)) {
            CleanupSheet(snapshotEmergencyArmed: true, onAction: { _ in }, onClose: {})
        })

        // Task 6 — Remote sheet. Fixed RemoteInfo (live session + a fixed Tailscale
        // IP) so the QR of the local attach command renders deterministically; steps
        // expanded so the golden covers the setup list too.
        cases.append(SnapshotCase("sheet-remote", size: CGSize(width: 480, height: 480)) {
            RemoteSheet(
                name: "Business",
                info: RemoteInfo(slug: "business", session: "claude-business", user: "alex",
                                 host: "studio.local", tailscaleIp: "100.92.18.4", alreadyRunning: true),
                snapshotStepsExpanded: true,
                onCopy: { _ in }, onClose: {})
        })

        // ── Phase 5: Menu-bar switcher, List view, States ──────────────────────

        // Task 3 — menu-bar switcher content (stand-in: native menu items render
        // empty headless). Alive-first rows + New Profile / Quit footer.
        cases.append(SnapshotCase("menu-content", size: CGSize(width: 240, height: 220)) {
            MenuContentSnapshot(profiles: Fixtures.all)
        })

        // Task 4 — dense List view. The REAL hand-built `ProfileListView` (it renders
        // headlessly now — no native `Table`), so the golden verifies what ships.
        // "research" selected so the coral selection wash shows.
        cases.append(SnapshotCase("list-view", size: CGSize(width: 760, height: 260), tolerance: 0.01) {
            ProfileListView(profiles: Fixtures.all, selection: .constant("research"))
        })

        // Task 5 — empty + loading states (shimmer frozen in snapshotMode).
        cases.append(SnapshotCase("state-empty", size: CGSize(width: 560, height: 400)) {
            EmptyStateView()
        })
        cases.append(SnapshotCase("state-loading", size: CGSize(width: 760, height: 420), tolerance: 0.01) {
            LoadingSkeletonView()
        })

        return cases
    }
}
