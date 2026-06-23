import SwiftUI
import ProfilesCore

/// The maximized single-profile detail page — the master-detail replacement for the
/// old right-side `.inspector` drill-down. Pushed onto the detail column's
/// `NavigationStack` when a sidebar row or a card's "Details ›" is tapped; the
/// system back button returns to the grid.
///
/// Composed from existing pieces so it can never drift from the cards / inspector:
///
/// - header — `BadgeDisc` + name + the same status line as the card, plus the
///   PRIMARY actions (Show Window + Remote for running/default, Open for stopped);
/// - the live metric row (CPU / MEMORY with `Sparkline`s), echoing the card layout;
/// - the shared `InstanceSections` drill-down (terminals + Throttle + leak block /
///   clean tiers + badge + Remove / terminals-only default) with the same
///   `InspectorAction` wiring the scene already performs.
///
/// Pure: no store/clock reads. The live `DashboardView` hands the rolling CPU/Mem
/// series + `AlertState`; the snapshot harness hands fixtures. The scrollable wrap
/// is gated behind `snapshotMode` because `ImageRenderer` collapses a `ScrollView`
/// to empty (same gotcha as SidebarView/ProfileListView/DashboardContent).
public struct ProfileDetailView: View {
    let stat: ProfileStat
    let cpu: [Double]
    let mem: [Double]
    let state: AlertState
    let terminals: [TerminalInfo]
    let onShowWindow: (String) -> Void
    let onRemote: (String) -> Void
    let onOpen: (String) -> Void
    let onAction: (InspectorAction) -> Void
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
                state: AlertState,
                terminals: [TerminalInfo],
                snapshotArmedDev: String? = nil,
                snapshotLeakArmed: Bool = false,
                snapshotRemoveExpanded: Bool = false,
                onShowWindow: @escaping (String) -> Void = { _ in },
                onRemote: @escaping (String) -> Void = { _ in },
                onOpen: @escaping (String) -> Void = { _ in },
                onAction: @escaping (InspectorAction) -> Void) {
        self.stat = stat
        self.cpu = cpu
        self.mem = mem
        self.state = state
        self.terminals = terminals
        self.snapshotArmedDev = snapshotArmedDev
        self.snapshotLeakArmed = snapshotLeakArmed
        self.snapshotRemoveExpanded = snapshotRemoveExpanded
        self.onShowWindow = onShowWindow
        self.onRemote = onRemote
        self.onOpen = onOpen
        self.onAction = onAction
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            header
            Divider().overlay(Theme.hairline)
            // Metrics are meaningful only while the instance is alive; a stopped
            // profile shows its sections (clean tiers / badge / remove) directly.
            if stat.running || stat.isDefault {
                metricRow
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

    // MARK: Header (identity + primary actions)

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
            primaryActions
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

    /// Running/default → Show Window + Remote; stopped → Open. Mirrors the card's
    /// primary action set (the secondary drill-down actions live in the sections).
    @ViewBuilder private var primaryActions: some View {
        HStack(spacing: Theme.Space.sm) {
            if stat.running || stat.isDefault {
                Button { onShowWindow(stat.effSlug) } label: { Text("Show Window") }
                    .buttonStyle(PillButtonStyle(.mint))
                    .accessibilityIdentifier("detail-\(stat.effSlug)-showwindow")
                Button { onRemote(stat.effSlug) } label: {
                    HStack(spacing: 5) {
                        if stat.remote { Circle().fill(Theme.mint).frame(width: 6, height: 6) }
                        Text("Remote")
                    }
                }
                .buttonStyle(PillButtonStyle(.neutral))
                .accessibilityIdentifier("detail-\(stat.effSlug)-remote")
            } else {
                Button { onOpen(stat.effSlug) } label: { Text("Open") }
                    .buttonStyle(PillButtonStyle(.mint))
                    .accessibilityIdentifier("detail-\(stat.effSlug)-open")
            }
        }
    }

    // MARK: Metric row (echoes the card's CPU / MEMORY cells)

    private var metricRow: some View {
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            metricCell(eyebrow: "CPU", value: formatCPU(stat.cpu), series: cpu, tint: Theme.cpuLine)
            metricCell(eyebrow: "MEMORY", value: formatMemoryMB(stat.mem), series: mem, tint: Theme.memLine)
        }
    }

    private func metricCell(eyebrow: String, value: String, series: [Double], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.text3)
            Text(value)
                .font(.system(size: 28, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
            Sparkline(values: series, tint: tint)
                .frame(height: 48)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
