import SwiftUI
import ProfilesCore

/// The state-routed drill-down sections shared by the old `.inspector` body
/// (`InspectorView`) and the maximized master-detail page (`ProfileDetailView`).
/// Pure: takes a `ProfileStat`, its loaded `terminals`, the precomputed
/// `AlertState`, and an `onAction` sink. The body switches by instance kind —
///
/// - running → terminals table + Throttle + (if leaking) the leak-restart block;
/// - stopped → clean tiers + badge picker + Remove (typed-DELETE flow);
/// - default → terminals ONLY (gated structurally by `isDefault`, CLAUDE.md §5).
///
/// Extracted from `InspectorView` so the maximized detail page reuses the exact
/// same sections (and the same `InspectorAction` wiring) instead of duplicating
/// them — keeping the existing `inspector-*` goldens byte-identical.
public struct InstanceSections: View {
    let stat: ProfileStat
    let terminals: [TerminalInfo]
    let state: AlertState
    let onAction: (InspectorAction) -> Void
    /// Snapshot-only: pre-arm one terminal's Close row so the armed state renders.
    let snapshotArmedDev: String?
    /// Snapshot-only: render the leak block's armed ("Confirm Restart") state.
    let snapshotLeakArmed: Bool
    /// Snapshot-only: render the remove control expanded with the name pre-filled.
    let snapshotRemoveExpanded: Bool

    public init(stat: ProfileStat,
                terminals: [TerminalInfo],
                state: AlertState,
                snapshotArmedDev: String? = nil,
                snapshotLeakArmed: Bool = false,
                snapshotRemoveExpanded: Bool = false,
                onAction: @escaping (InspectorAction) -> Void) {
        self.stat = stat
        self.terminals = terminals
        self.state = state
        self.snapshotArmedDev = snapshotArmedDev
        self.snapshotLeakArmed = snapshotLeakArmed
        self.snapshotRemoveExpanded = snapshotRemoveExpanded
        self.onAction = onAction
    }

    public var body: some View {
        if stat.isDefault {
            // Restricted default: terminals ONLY — no throttle/leak/clean/badge/remove.
            terminalsSection
        } else if stat.running {
            runningBody
        } else {
            stoppedBody
        }
    }

    private var stoppedBody: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            CleanTiers(disk: stat.disk) { onAction(.clean($0)) }
            BadgePicker(currentHex: stat.color, slug: stat.slug) { onAction(.setBadge($0)) }
            Divider().overlay(Theme.hairline)
            RemoveProfile(name: stat.name, snapshotExpanded: snapshotRemoveExpanded) {
                onAction(.remove)
            }
        }
    }

    private var terminalsSection: some View {
        TerminalsTable(terminals: terminals, snapshotArmedDev: snapshotArmedDev) {
            onAction(.closeTerminal($0))
        }
    }

    private var runningBody: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            terminalsSection

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Button { onAction(.throttle) } label: { Text("Throttle CPU") }
                    .buttonStyle(PillButtonStyle(.neutral))
                    .accessibilityIdentifier("inspector-throttle")
                Text("Lowers priority until restart.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
            }

            if stat.ptmx > 0 {
                LeakBlock(stat: stat, state: state, snapshotArmed: snapshotLeakArmed) {
                    onAction(.restart)
                }
            }
        }
    }
}
