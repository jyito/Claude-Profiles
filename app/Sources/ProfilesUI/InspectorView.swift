import SwiftUI
import ProfilesCore

/// Actions an inspector body can request. The view stays pure — it never calls the
/// engine itself; the scene maps each case to the right `engine.run([...])`/refresh.
public enum InspectorAction: Equatable, Sendable {
    case closeTerminal(String)   // dev path → engine closeterm <slug> <dev>
    case throttle                // engine throttle <slug>
    case restart                 // engine restart <slug>
    case clean(String)           // tier (caches|gpu|logs|all) → engine clean <slug> <tier>
    case setBadge(Int)           // palette index → engine setbadge <slug> <index>
    case remove                  // engine remove <slug> + purge <slug>
}

/// The right-side `.inspector` drill-down body. Pure: takes a `ProfileStat`, its
/// loaded `terminals`, the precomputed `AlertState`, and an `onAction` sink. The
/// body switches by instance kind — running profile, stopped profile, or the
/// restricted default instance (terminals-only, gated structurally by `isDefault`).
public struct InspectorView: View {
    let stat: ProfileStat
    let terminals: [TerminalInfo]
    let state: AlertState
    let onAction: (InspectorAction) -> Void
    /// Snapshot-only: pre-arm one terminal's Close row so the armed state renders.
    let snapshotArmedDev: String?

    @Environment(\.snapshotMode) private var snapshotMode

    public init(stat: ProfileStat,
                terminals: [TerminalInfo],
                state: AlertState,
                snapshotArmedDev: String? = nil,
                onAction: @escaping (InspectorAction) -> Void) {
        self.stat = stat
        self.terminals = terminals
        self.state = state
        self.snapshotArmedDev = snapshotArmedDev
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            header
            Divider().overlay(Theme.hairline)
            stateBody
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas)
    }

    // MARK: Header (echoes the card identity)

    private var header: some View {
        HStack(spacing: Theme.Space.md) {
            BadgeDisc(stat: stat, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                statusLine
            }
            Spacer(minLength: 0)
        }
    }

    private var statusLine: some View {
        HStack(spacing: Theme.Space.xs) {
            StatusDot(running: stat.running, size: 7)
            Text(statusText)
                .font(.system(size: 11))
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
        return "Stopped · opened \(stat.opens)×"
    }

    // MARK: Body routing
    //
    // running → terminals table (+ throttle + leak block, Task 5);
    // stopped → clean tiers + badge picker + remove (Tasks 6–7);
    // default → terminals ONLY (gated structurally by isDefault — Task 8).
    // Snapshot-only `snapshotArmedDev` pre-arms one Close row for the golden.

    @ViewBuilder private var stateBody: some View {
        if stat.isDefault {
            terminalsSection
        } else if stat.running {
            terminalsSection
        } else {
            // Stopped body (clean tiers + badge + remove) assembled in Tasks 6–7.
            EmptyView()
        }
    }

    private var terminalsSection: some View {
        TerminalsTable(terminals: terminals, snapshotArmedDev: snapshotArmedDev) {
            onAction(.closeTerminal($0))
        }
    }
}
