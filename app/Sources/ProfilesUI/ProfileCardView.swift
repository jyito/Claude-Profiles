import SwiftUI
import ProfilesCore

/// One profile card. Renders the running / stopped / default layout off a
/// `ProfileStat` + precomputed `AlertState` + rolling CPU/Mem series. Deterministic:
/// no time/env/material reads inside the snapshotted content.
public struct ProfileCardView: View {
    let stat: ProfileStat
    let cpu: [Double]
    let mem: [Double]
    let state: AlertState
    let selected: Bool
    let onDetails: (String) -> Void

    public init(stat: ProfileStat, cpu: [Double], mem: [Double], state: AlertState,
                selected: Bool = false, onDetails: @escaping (String) -> Void = { _ in }) {
        self.stat = stat
        self.cpu = cpu
        self.mem = mem
        self.state = state
        self.selected = selected
        self.onDetails = onDetails
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            identityRow
            content
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The severity accent border. Coral is reserved for `.critical` (≥90%);
    /// `.warning` reads amber; `.calm` (and the restricted default instance) get
    /// no accent. The coral *selection* ring is a separate concern handled below.
    private var severityStroke: (color: Color, width: CGFloat)? {
        guard !stat.isDefault else { return nil }
        switch state {
        case .warning: return (Theme.amber, 1.5)
        case .critical: return (Theme.coral, 1.5)
        case .calm: return nil
        }
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
            // Overflow (Quit/Force/Restart) is wired in Phase 3; a plain glyph
            // button renders deterministically where a `Menu` paints empty headless.
            Button {
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card-\(stat.effSlug)-overflow")
        }
    }

    // MARK: Variant routing

    @ViewBuilder private var content: some View {
        if stat.isDefault {
            defaultContent
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
            } label: {
                Text("Show Window")
            }
            .buttonStyle(PillButtonStyle(.mint))
            .accessibilityIdentifier("card-\(stat.effSlug)-showwindow")

            Button {
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

    // MARK: Default (filled in Task 6)

    private var defaultContent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            statusLine
            metricRow
            // NOTE: structurally no disk / clean tiers / badge / leak-restart — the
            // restricted default contract (CLAUDE.md §5) is unbreakable here.
            HStack(spacing: Theme.Space.sm) {
                Button {
                } label: { Text("Show Window") }
                    .buttonStyle(PillButtonStyle(.mint))
                    .accessibilityIdentifier("card-default-showwindow")
                Button {
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
}
