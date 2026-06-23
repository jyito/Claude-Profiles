import SwiftUI
import ProfilesCore

/// Lifecycle actions raised by a card's overflow (ellipsis) menu. The scene maps
/// these to engine verbs (accounting for the default instance) and confirms the
/// disruptive ones before firing.
public enum CardAction: Sendable, Equatable {
    case quit, force, restart
}

/// One profile card. Renders the running / stopped / default layout off a
/// `ProfileStat` + precomputed `AlertState` + rolling CPU/Mem series. Deterministic:
/// no time/env/material reads inside the snapshotted content.
public struct ProfileCardView: View {
    @Environment(\.snapshotMode) private var snapshotMode

    let stat: ProfileStat
    let cpu: [Double]
    let mem: [Double]
    let state: AlertState
    let selected: Bool
    let onDetails: (String) -> Void
    let onRemote: (String) -> Void
    /// Running/default: raise the instance's windows by PID (in-process focus).
    let onShowWindow: (String) -> Void
    /// Stopped: launch the wrapper (`engine open <slug>`).
    let onOpen: (String) -> Void
    /// Overflow menu (running/default only): Restart / Quit / Force Quit.
    let onCardAction: (CardAction) -> Void
    /// When true (the grid), the card SURFACE stretches to fill its cell so every card
    /// in a row is exactly the same height regardless of content. False (single-card
    /// snapshots) keeps natural height.
    let fillsHeight: Bool

    public init(stat: ProfileStat, cpu: [Double], mem: [Double], state: AlertState,
                selected: Bool = false, onDetails: @escaping (String) -> Void = { _ in },
                onRemote: @escaping (String) -> Void = { _ in },
                onShowWindow: @escaping (String) -> Void = { _ in },
                onOpen: @escaping (String) -> Void = { _ in },
                onCardAction: @escaping (CardAction) -> Void = { _ in },
                fillsHeight: Bool = false) {
        self.stat = stat
        self.cpu = cpu
        self.mem = mem
        self.state = state
        self.selected = selected
        self.onDetails = onDetails
        self.onRemote = onRemote
        self.onShowWindow = onShowWindow
        self.onOpen = onOpen
        self.onCardAction = onCardAction
        self.fillsHeight = fillsHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            identityRow
            content
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .background(cardSurface)
        .overlay(cardStroke)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .opacity(stat.running || stat.isDefault ? 1.0 : 0.6)
    }

    // MARK: Surfaces / stroke

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.surface1)
    }

    /// The leak accent border: amber when actively leaking, nothing otherwise. There's
    /// no coral tier anymore — a leak is a leak. The restricted default instance never
    /// gets the accent border (its leak shows as an informational line in-card). The
    /// coral *selection* ring is a separate concern handled below.
    private var severityStroke: (color: Color, width: CGFloat)? {
        guard !stat.isDefault else { return nil }
        return state == .leaking ? (Theme.amber, 1.5) : nil
    }

    private var cardStroke: some View {
        // Selection (coral) wins over severity so the focused card always reads as
        // selected; otherwise the severity accent, else the resting hairline.
        let resolved: (Color, CGFloat) = selected
            ? (Theme.coral, 1.5)
            : (severityStroke ?? (Theme.hairline, 1))
        return RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(resolved.0, lineWidth: resolved.1)
    }

    // MARK: Identity row (shared)

    private var identityRow: some View {
        HStack(spacing: Theme.Space.md) {
            BadgeDisc(stat: stat, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(stat.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if stat.isDefault {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill").font(.system(size: 8))
                        Text("System")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.text3)
                }
            }
            Spacer(minLength: Theme.Space.sm)
            // Overflow (Restart / Quit / Force Quit) — running instances only; a
            // stopped profile has nothing to quit/restart, so it gets no menu.
            if showsOverflow {
                overflowControl
            }
        }
    }

    /// Only running instances (running profile OR the running default) expose the
    /// lifecycle overflow — there's nothing to quit/restart on a stopped card.
    private var showsOverflow: Bool { stat.running }

    private var overflowGlyph: some View {
        Image(systemName: "ellipsis.circle")
            .font(.system(size: 16))
            .foregroundStyle(Theme.text3)
    }

    /// Native `Menu` live; a plain glyph under `ImageRenderer` (a `Menu` paints empty
    /// headless, so snapshotMode keeps the deterministic glyph — goldens unchanged).
    @ViewBuilder private var overflowControl: some View {
        if snapshotMode {
            overflowGlyph
                .accessibilityIdentifier("card-\(stat.effSlug)-overflow")
        } else {
            Menu {
                Button("Restart") { onCardAction(.restart) }
                Button("Quit") { onCardAction(.quit) }
                Button("Force Quit", role: .destructive) { onCardAction(.force) }
            } label: {
                overflowGlyph
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("card-\(stat.effSlug)-overflow")
        }
    }

    // MARK: Variant routing

    @ViewBuilder private var content: some View {
        if stat.isDefault {
            if stat.running { defaultContent } else { defaultStoppedContent }
        } else if stat.running {
            runningContent
        } else {
            stoppedContent
        }
    }

    // MARK: Running

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            statusLine
            metricRow
            HandleGauge(used: stat.ptmx, max: stat.ptmxMax, state: state)
            actionRow
        }
    }

    private var statusLine: some View {
        HStack(spacing: Theme.Space.sm) {
            StatusDot(running: true)
            (Text("Running").foregroundColor(Theme.mint)
             + Text(" · \(stat.procs) Procs · \(stat.ptys) Terminals").foregroundColor(Theme.text3))
                .font(.system(size: 12))
                .monospacedDigit()
        }
    }

    private var metricRow: some View {
        HStack(alignment: .top, spacing: Theme.Space.lg) {
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
                .font(.title2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
            Sparkline(values: series, tint: tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        HStack(spacing: Theme.Space.sm) {
            Button {
                onShowWindow(stat.effSlug)
            } label: {
                Text("Show Window")
            }
            .buttonStyle(PillButtonStyle(.mint))
            .accessibilityIdentifier("card-\(stat.effSlug)-showwindow")

            Button {
                onRemote(stat.effSlug)
            } label: {
                HStack(spacing: 5) {
                    if stat.remote {
                        Circle().fill(Theme.mint).frame(width: 6, height: 6)
                    }
                    Text("Remote")
                }
            }
            .buttonStyle(PillButtonStyle(.neutral))
            .accessibilityIdentifier("card-\(stat.effSlug)-remote")

            Spacer(minLength: 0)

            Button {
                onDetails(stat.effSlug)
            } label: {
                HStack(spacing: 2) {
                    Text("Details")
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Theme.text2)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card-\(stat.effSlug)-details")
        }
        .font(.system(size: 12, weight: .medium))
    }

    // MARK: Stopped (filled in Task 6)

    private var stoppedContent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.sm) {
                StatusDot(running: false)
                Text("Stopped · opened \(stat.opens)× · last \(stat.last)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text3)
            }
            LabeledContent {
                Text(formatDiskMB(stat.disk))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text2)
            } label: {
                Text("Disk")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
            }
            Sparkline.ghosted(cpu)
            HStack(spacing: Theme.Space.sm) {
                Button {
                    onOpen(stat.effSlug)
                } label: { Text("Open") }
                    .buttonStyle(PillButtonStyle(.mint))
                    .accessibilityIdentifier("card-\(stat.effSlug)-open")
                Spacer(minLength: 0)
                Button {
                    onDetails(stat.effSlug)
                } label: {
                    HStack(spacing: 2) {
                        Text("Details")
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Theme.text2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("card-\(stat.effSlug)-details")
            }
            .font(.system(size: 12, weight: .medium))
        }
    }

    // MARK: Default

    /// The informational leak line under the default card's metrics. Honors the
    /// restricted-default contract (CLAUDE.md §5) — DISPLAY-ONLY from the engine's
    /// `ptmx`, no restart/clean/Details affordance. Leaking → amber "⚠ N leaked"; calm
    /// → the read-only note with a muted "· N handles" tail so the count is always
    /// visible without ever implying an action.
    @ViewBuilder private var defaultLeakLine: some View {
        if state == .leaking {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text("\(stat.ptmx) leaked")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.amber)
                Text("· read-only, can't restart the default")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
            }
            .accessibilityIdentifier("card-default-leak")
        } else {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text3)
                Text("Read-only · protected")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                    .layoutPriority(1)
                Text("· \(stat.ptmx) handles")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text4)
            }
            .accessibilityIdentifier("card-default-leak")
        }
    }

    private var defaultContent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            statusLine
            metricRow
            // Structurally no disk / clean tiers / badge / leak-RESTART — the
            // restricted default contract (CLAUDE.md §5) is unbreakable here. The
            // line below the metrics is INFORMATIONAL only: it reads the engine's
            // `ptmx` (a process metric, never the data dir) and surfaces an active
            // leak in amber, but offers NO restart/clean/Details CTA. It also fills
            // the handle-gauge slot so the default card matches running cards' height.
            defaultLeakLine
            HStack(spacing: Theme.Space.sm) {
                Button {
                    onShowWindow(stat.effSlug)
                } label: { Text("Show Window") }
                    .buttonStyle(PillButtonStyle(.mint))
                    .accessibilityIdentifier("card-default-showwindow")
                Button {
                    onRemote(stat.effSlug)
                } label: {
                    HStack(spacing: 5) {
                        if stat.remote { Circle().fill(Theme.mint).frame(width: 6, height: 6) }
                        Text("Remote")
                    }
                }
                .buttonStyle(PillButtonStyle(.neutral))
                .accessibilityIdentifier("card-default-remote")
                Spacer(minLength: 0)
                Button {
                    onDetails(stat.effSlug)
                } label: {
                    HStack(spacing: 2) {
                        Text("Details")
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Theme.text2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("card-default-details")
            }
            .font(.system(size: 12, weight: .medium))
        }
    }

    // MARK: Default — stopped

    /// The default instance after the user quits it. The engine reports it
    /// `running:false`; this is the relaunch affordance (the bug fix — the card used
    /// to stay stuck reading "Running · 0 Procs" with a dead Show Window button).
    ///
    /// Honors the SAME restricted default contract as `defaultContent` (CLAUDE.md §5):
    /// structurally NO clean tiers, NO Details drill-down, NO badge picker, NO disk
    /// read. Just a stopped status line, the protected note (kept for visual parity
    /// with the running default), and an Open (→ `opendefault`) + Remote action row.
    /// No metric row / sparklines — the instance is off. `fillsHeight` equalizes the
    /// card height in the grid, so this stays deliberately lightweight.
    private var defaultStoppedContent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.sm) {
                StatusDot(running: false)
                Text("Stopped · default instance")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text3)
            }
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text3)
                Text("Read-only · default instance is protected")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
            }
            HStack(spacing: Theme.Space.sm) {
                Button {
                    onOpen(stat.effSlug)
                } label: { Text("Open") }
                    .buttonStyle(PillButtonStyle(.mint))
                    .accessibilityIdentifier("card-default-open")
                Button {
                    onRemote(stat.effSlug)
                } label: {
                    HStack(spacing: 5) {
                        if stat.remote { Circle().fill(Theme.mint).frame(width: 6, height: 6) }
                        Text("Remote")
                    }
                }
                .buttonStyle(PillButtonStyle(.neutral))
                .accessibilityIdentifier("card-default-remote")
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .medium))
        }
    }
}
