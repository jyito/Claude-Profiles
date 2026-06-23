import SwiftUI
import Charts
import ProfilesCore

/// The maximized single-profile detail page — the master-detail replacement for the
/// old right-side `.inspector` drill-down. Pushed onto the detail column's
/// `NavigationStack` when a sidebar row or a card's "Details ›" is tapped; the
/// system back button returns to the grid.
///
/// Composed from existing pieces so it can never drift from the cards / inspector:
///
/// - header — `BadgeDisc` + name + the same status line as the card;
/// - a consolidated ACTION BAR directly below the header, holding the quick
///   lifecycle actions in ONE row: running/default → Show Window · Remote ·
///   Throttle CPU · Restart · a `⋯` overflow with Quit / Force Quit; stopped →
///   Open · Remote (nothing to throttle/restart/quit). This is the single home for
///   the quick actions (they were previously split between the header and the
///   sections below the terminals table);
/// - the live metric row (CPU / MEMORY with `Sparkline`s), echoing the card layout;
/// - the shared `InstanceSections` drill-down (terminals + leak block / clean tiers
///   + badge + Remove / terminals-only default) with the same `InspectorAction`
///   wiring the scene already performs. Throttle no longer lives there — it moved up
///   into the action bar — so the sections are pure drill-down content.
///
/// Pure: no store/clock reads. The live `DashboardView` hands the rolling CPU/Mem
/// series + `AlertState`; the snapshot harness hands fixtures. The scrollable wrap
/// is gated behind `snapshotMode` because `ImageRenderer` collapses a `ScrollView`
/// to empty (same gotcha as SidebarView/ProfileListView/DashboardContent).
public struct ProfileDetailView: View {
    let stat: ProfileStat
    let cpu: [Double]
    let mem: [Double]
    /// Rolling leaked-handle (ptmx) history — drives the handle hero trend.
    let ptmx: [Double]
    let state: AlertState
    let terminals: [TerminalInfo]
    let onShowWindow: (String) -> Void
    let onRemote: (String) -> Void
    let onOpen: (String) -> Void
    let onAction: (InspectorAction) -> Void
    /// Lifecycle overflow (Quit / Force Quit), keyed off the same `CardAction` the
    /// cards emit. The scene owns the confirmation + default-verb mapping (so the
    /// detail page stays pure of engine calls, exactly like the cards).
    let onCardAction: (CardAction) -> Void
    /// Snapshot-only: pre-arm one terminal's Close row so the armed state renders.
    let snapshotArmedDev: String?
    /// Snapshot-only: render the leak block's armed ("Confirm Restart") state.
    let snapshotLeakArmed: Bool
    /// Snapshot-only: render the remove control expanded with the name pre-filled.
    let snapshotRemoveExpanded: Bool

    @Environment(\.snapshotMode) private var snapshotMode

    public init(stat: ProfileStat,
                cpu: [Double],
                mem: [Double],
                ptmx: [Double] = [],
                state: AlertState,
                terminals: [TerminalInfo],
                snapshotArmedDev: String? = nil,
                snapshotLeakArmed: Bool = false,
                snapshotRemoveExpanded: Bool = false,
                onShowWindow: @escaping (String) -> Void = { _ in },
                onRemote: @escaping (String) -> Void = { _ in },
                onOpen: @escaping (String) -> Void = { _ in },
                onCardAction: @escaping (CardAction) -> Void = { _ in },
                onAction: @escaping (InspectorAction) -> Void) {
        self.stat = stat
        self.cpu = cpu
        self.mem = mem
        // Default to the live ptmx sample so the trend is never empty (e.g. a
        // first-tick profile or a caller that hasn't wired the series yet).
        self.ptmx = ptmx.isEmpty ? [Double(stat.ptmx)] : ptmx
        self.state = state
        self.terminals = terminals
        self.snapshotArmedDev = snapshotArmedDev
        self.snapshotLeakArmed = snapshotLeakArmed
        self.snapshotRemoveExpanded = snapshotRemoveExpanded
        self.onShowWindow = onShowWindow
        self.onRemote = onRemote
        self.onOpen = onOpen
        self.onCardAction = onCardAction
        self.onAction = onAction
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            header
            actionBar
            Divider().overlay(Theme.hairline)
            // Metrics are meaningful only while the instance is alive; a stopped
            // profile shows its sections (clean tiers / badge / remove) directly.
            if stat.running || stat.isDefault {
                heroCharts
                statStrip
            }
            InstanceSections(
                stat: stat,
                terminals: terminals,
                state: state,
                snapshotArmedDev: snapshotArmedDev,
                snapshotLeakArmed: snapshotLeakArmed,
                snapshotRemoveExpanded: snapshotRemoveExpanded,
                onAction: onAction
            )
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    public var body: some View {
        // `ImageRenderer` proposes a nil height into a `ScrollView`, collapsing its
        // content to empty — so render the bare VStack under the snapshot and only
        // wrap it in a live `ScrollView` for the real, scrollable app.
        Group {
            if snapshotMode {
                content
            } else {
                ScrollView { content }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas)
        .navigationTitle(stat.name)
        .accessibilityIdentifier("profile-detail-\(stat.effSlug)")
    }

    // MARK: Header (identity)

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.lg) {
            BadgeDisc(stat: stat, size: 48)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(stat.name)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                statusLine
            }
            Spacer(minLength: Theme.Space.lg)
        }
    }

    private var statusLine: some View {
        HStack(spacing: Theme.Space.xs) {
            StatusDot(running: stat.running, size: 8)
            Text(statusText)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(stat.running ? Theme.mint : Theme.text3)
        }
    }

    private var statusText: String {
        if stat.isDefault {
            return "System · \(stat.procs) Procs · \(stat.ptys) Terminals"
        }
        if stat.running {
            return "Running · \(stat.procs) Procs · \(stat.ptys) Terminals"
        }
        return "Stopped · opened \(stat.opens)× · last \(stat.last)"
    }

    // MARK: Action bar (consolidated quick actions)

    /// The single home for the profile's quick lifecycle actions, directly below the
    /// header. Running/default → Show Window · Remote · Throttle CPU · Restart · a `⋯`
    /// overflow (Quit / Force Quit); stopped → Open · Remote (there's nothing to
    /// throttle/restart/quit on a stopped instance — Remove stays in its section).
    /// Throttle/Restart go through `onAction` (`InspectorAction`); Quit/Force Quit go
    /// through `onCardAction` (the scene confirms + maps the default verbs).
    @ViewBuilder private var actionBar: some View {
        HStack(spacing: Theme.Space.sm) {
            // Show-Window vs Open keys off `running`, NOT `isDefault` — a quit default
            // (engine reports `running:false`) must offer Open (→ opendefault), not a
            // dead Show Window. Throttle/Restart/overflow stay running-only: a stopped
            // instance has nothing to throttle, restart, or quit.
            if stat.running {
                Button { onShowWindow(stat.effSlug) } label: { Text("Show Window") }
                    .buttonStyle(PillButtonStyle(.mint))
                    .accessibilityIdentifier("detail-\(stat.effSlug)-showwindow")
                remoteButton
                Button { onAction(.throttle) } label: { Text("Throttle CPU") }
                    .buttonStyle(PillButtonStyle(.neutral))
                    .accessibilityIdentifier("detail-\(stat.effSlug)-throttle")
                Button { onAction(.restart) } label: { Text("Restart") }
                    .buttonStyle(PillButtonStyle(.neutral))
                    .accessibilityIdentifier("detail-\(stat.effSlug)-restart")
                overflowControl
            } else {
                Button { onOpen(stat.effSlug) } label: { Text("Open") }
                    .buttonStyle(PillButtonStyle(.mint))
                    .accessibilityIdentifier("detail-\(stat.effSlug)-open")
                remoteButton
            }
            Spacer(minLength: 0)
        }
    }

    /// Remote pill with the mint live-dot when the profile's Claude Code session is
    /// up. Shared by both action-bar variants (running/default and stopped).
    private var remoteButton: some View {
        Button { onRemote(stat.effSlug) } label: {
            HStack(spacing: 5) {
                if stat.remote { Circle().fill(Theme.mint).frame(width: 6, height: 6) }
                Text("Remote")
            }
        }
        .buttonStyle(PillButtonStyle(.neutral))
        .accessibilityIdentifier("detail-\(stat.effSlug)-remote")
    }

    private var overflowGlyph: some View {
        Image(systemName: "ellipsis.circle")
            .font(.system(size: 16))
            .foregroundStyle(Theme.text3)
    }

    /// Native `Menu` live; a plain glyph under `ImageRenderer` (a `Menu` paints empty
    /// headless, so snapshotMode keeps the deterministic glyph — same pattern as the
    /// card's overflow, goldens stay clean).
    @ViewBuilder private var overflowControl: some View {
        if snapshotMode {
            overflowGlyph
                .accessibilityIdentifier("detail-\(stat.effSlug)-overflow")
        } else {
            Menu {
                Button("Quit") { onCardAction(.quit) }
                Button("Force Quit", role: .destructive) { onCardAction(.force) }
            } label: {
                overflowGlyph
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("detail-\(stat.effSlug)-overflow")
        }
    }

    // MARK: Hero trend charts (CPU · Memory · Handle pool)

    /// Three taller-than-the-card trend charts in a row. CPU keeps its coral metric
    /// identity, Memory its teal; the handle chart carries the amber leak verdict
    /// (with a dashed ceiling rule). The default instance is read-only, so its handle
    /// verdict is informational only.
    private var heroCharts: some View {
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            HeroTrend(eyebrow: "CPU",
                      value: formatCPU(stat.cpu),
                      sub: cpuSub,
                      subTint: Theme.text3,
                      series: cpu,
                      tint: Theme.cpuLine)
                .accessibilityIdentifier("detail-\(stat.effSlug)-trend-cpu")
            HeroTrend(eyebrow: "MEMORY",
                      value: formatMemoryMB(stat.mem),
                      sub: memSub,
                      subTint: Theme.text3,
                      series: mem,
                      tint: Theme.memLine)
                .accessibilityIdentifier("detail-\(stat.effSlug)-trend-mem")
            HeroTrend(eyebrow: "HANDLE POOL",
                      value: "\(stat.ptmx) / \(stat.ptmxMax)",
                      sub: leakVerdict.text,
                      subTint: leakVerdict.tint,
                      series: ptmx,
                      tint: Theme.amber,
                      ceiling: Double(stat.ptmxMax))
                .accessibilityIdentifier("detail-\(stat.effSlug)-trend-handles")
        }
    }

    /// "peak {max}% · last {N}s" — N is the window length at the 2s tick cadence.
    private var cpuSub: String {
        let peak = cpu.max() ?? stat.cpu
        let secs = max(cpu.count, 1) * 2
        return "peak \(formatCPU(peak)) · last \(secs)s"
    }

    /// A short delta over the window when the series has ≥2 points; otherwise the
    /// bare value (keeps the line meaningful on a first-tick profile).
    private var memSub: String {
        guard let first = mem.first, let last = mem.last, mem.count >= 2 else {
            return formatMemoryMB(stat.mem)
        }
        let delta = last - first
        if abs(delta) < 1 { return "flat over \(mem.count * 2)s" }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(formatMemoryMB(abs(delta))) over \(mem.count * 2)s"
    }

    /// The leak verdict sub-line under the handle chart, derived from `AlertState`.
    /// Amber-only — there's no coral/critical tier. The DEFAULT instance is read-only
    /// (never auto-restarted, CLAUDE.md §5) so its leaking verdict is informational
    /// ("▲ leaking") rather than the actionable "restart frees them".
    private var leakVerdict: (text: String, tint: Color) {
        switch state {
        case .calm:
            return ("✓ no active leak", Theme.text3)
        case .leaking:
            return stat.isDefault
                ? ("▲ leaking", Theme.amber)
                : ("▲ leaking — restart frees them", Theme.amber)
        }
    }

    // MARK: Stat strip (surface1 band of hairline-divided cells)

    /// A KPI-strip-style band of secondary facts the hero charts don't carry:
    /// process/terminal counts, on-disk size, lifetime opens, last launch, and the
    /// Remote session state (mint live-dot). Disk shows "—" for the default sentinel.
    private var statStrip: some View {
        HStack(spacing: 0) {
            statCell(eyebrow: "PROCS", value: "\(stat.procs)")
            statDivider
            statCell(eyebrow: "TERMINALS", value: "\(stat.ptys)")
            statDivider
            statCell(eyebrow: "DISK", value: formatDiskMB(stat.disk))
            statDivider
            statCell(eyebrow: "OPENED", value: "\(stat.opens)×")
            statDivider
            statCell(eyebrow: "LAST LAUNCH", value: stat.last.isEmpty ? "—" : stat.last)
            statDivider
            remoteCell
        }
        .padding(.vertical, Theme.Space.md)
        .padding(.horizontal, Theme.Space.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .accessibilityIdentifier("detail-\(stat.effSlug)-statstrip")
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 32)
            .padding(.horizontal, Theme.Space.sm)
    }

    private func statCell(eyebrow: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.text3)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var remoteCell: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("REMOTE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.text3)
            HStack(spacing: 5) {
                if stat.remote {
                    Circle().fill(Theme.mint).frame(width: 6, height: 6)
                    Text("live")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.mint)
                } else {
                    Text("idle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - HeroTrend

/// One detail-page hero trend chart: an eyebrow, a big monospaced value, a sub-line,
/// and a ~56pt `LineMark` + `AreaMark` + live `PointMark` (taller than the card
/// sparklines). Axes/legend hidden, Y pinned. An optional dashed `RuleMark` marks a
/// ceiling (the handle pool's `ptmxMax`) so a climbing trend reads against its limit.
private struct HeroTrend: View {
    let eyebrow: String
    let value: String
    let sub: String
    let subTint: Color
    let series: [Double]
    let tint: Color
    /// Optional dashed ceiling line (e.g. the ptmx max). The Y domain expands to
    /// include it so the rule is always visible above the trend.
    var ceiling: Double? = nil

    /// Pin Y to 0…max(series, ceiling) so per-core CPU >100% never flattens and the
    /// ceiling rule stays on-chart.
    private var yMax: Double {
        let s = series.max() ?? 1
        return Swift.max(s, ceiling ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.text3)
            Text(value)
                .font(.title2.monospacedDigit())
                .foregroundStyle(Theme.text)
            chart
                .frame(height: 56)
            Text(sub)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(subTint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        Chart {
            if let ceiling {
                RuleMark(y: .value("ceiling", ceiling))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Theme.text4)
            }
            ForEach(Array(series.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", v))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)
                AreaMark(x: .value("i", i), y: .value("v", v))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [tint.opacity(0.30), tint.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            if let last = series.indices.last {
                PointMark(x: .value("i", last), y: .value("v", series[last]))
                    .symbol(.circle)
                    .symbolSize(32)
                    .foregroundStyle(tint)
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}
