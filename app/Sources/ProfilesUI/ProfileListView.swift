import SwiftUI
import ProfilesCore

/// The detail column's layout mode — the toolbar Grid/List segmented control
/// toggles between the card grid (default) and the dense `ProfileListView`. Both
/// render the same `store.profiles` + share `selection`, so the inspector works
/// in either.
public enum ProfileViewMode: String, CaseIterable, Identifiable, Sendable {
    case grid, list
    public var id: String { rawValue }
    public var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
    public var label: String { self == .grid ? "Grid" : "List" }
}

/// The dense List-view alternative to the card grid. A hand-built header + row
/// stack over the same `ProfileStat` models, with `selection` bound to the same
/// `String?` slug so the inspector works identically in either view mode.
///
/// Columns: identity (dot · badge · name) · status · CPU% · MEM · terminals ·
/// handle-pool (used/ceiling). Numeric columns are monospacedDigit so they don't
/// jitter as live values tick.
///
/// Hand-built rather than a native `Table`: the native Table renders EMPTY under
/// `ImageRenderer` (like `Menu`/`Form`), so it was never visually verified and
/// shipped as blank striped rows in the live app. This layout (promoted from the
/// former `ProfileListSnapshotContent`) renders headlessly AND is interactive —
/// each row taps to set `selection`, with the coral selection wash — so the golden
/// tests the real view.
public struct ProfileListView: View {
    let profiles: [ProfileStat]
    @Binding var selection: String?

    public init(profiles: [ProfileStat], selection: Binding<String?>) {
        self.profiles = profiles
        self._selection = selection
    }

    private var ordered: [ProfileStat] { sortProfiles(profiles) }

    // Column widths read true against the identity column (which fills remaining width).
    private enum Col {
        static let status: CGFloat = 84
        static let cpu: CGFloat = 64
        static let mem: CGFloat = 88
        static let term: CGFloat = 76
        static let handles: CGFloat = 88
    }

    private func headerCell(_ s: String, width: CGFloat, align: Alignment = .leading) -> some View {
        Text(s.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Theme.text3)
            .frame(width: width, alignment: align)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.md) {
            Text("PROFILE")
                .font(.system(size: 10, weight: .semibold)).tracking(0.5)
                .foregroundStyle(Theme.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
            headerCell("Status", width: Col.status)
            headerCell("CPU", width: Col.cpu, align: .trailing)
            headerCell("Memory", width: Col.mem, align: .trailing)
            headerCell("Terms", width: Col.term, align: .trailing)
            headerCell("Handles", width: Col.handles, align: .trailing)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }

    private func numCell(_ s: String, width: CGFloat) -> some View {
        Text(s)
            .font(.system(size: 12)).monospacedDigit()
            .foregroundStyle(Theme.text2)
            .frame(width: width, alignment: .trailing)
    }

    private func row(_ stat: ProfileStat) -> some View {
        let isSel = selection == stat.effSlug
        return HStack(spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.sm) {
                StatusDot(running: stat.running, size: 7)
                BadgeDisc(stat: stat, size: 18)
                Text(stat.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(stat.running ? "Running" : "Stopped")
                .font(.system(size: 12))
                .foregroundStyle(stat.running ? Theme.mint : Theme.text3)
                .frame(width: Col.status, alignment: .leading)

            numCell(stat.running ? formatCPU(stat.cpu) : "—", width: Col.cpu)
            numCell(stat.running ? formatMemoryMB(stat.mem) : "—", width: Col.mem)
            numCell(stat.running ? "\(stat.ptys)" : "—", width: Col.term)
            numCell(stat.running ? "\(stat.ptmx)/\(stat.ptmxMax)" : "—", width: Col.handles)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(isSel ? Theme.coral.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { selection = stat.effSlug }
        .accessibilityIdentifier("list-row-\(stat.effSlug)")
    }

    @Environment(\.snapshotMode) private var snapshotMode

    private var rows: some View {
        VStack(spacing: 1) {
            ForEach(ordered) { stat in
                row(stat)
                if stat.id != ordered.last?.id {
                    Divider().overlay(Theme.hairline).padding(.horizontal, Theme.Space.md)
                }
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            // `ImageRenderer` (the snapshot harness) proposes a nil height into a
            // `ScrollView`, collapsing its content to empty — the very blank-rows
            // bug we're fixing. So render the rows directly under the snapshot, and
            // only wrap them in a live `ScrollView` for the real, scrollable app.
            if snapshotMode {
                rows
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    rows
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas)
        .accessibilityIdentifier("profile-table")
    }
}
