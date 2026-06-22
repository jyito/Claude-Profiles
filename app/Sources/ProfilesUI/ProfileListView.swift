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

/// The dense List-view alternative to the card grid. A native `Table` over the
/// same `ProfileStat` models, with `selection` bound to the same `String?` slug
/// so the inspector works identically in either view mode.
///
/// Columns: identity (dot · badge · name) · status · CPU% · MEM · terminals ·
/// handle-pool (used/ceiling). Numeric columns are monospacedDigit so they don't
/// jitter as live values tick.
///
/// The native `Table` renders empty under `ImageRenderer` (like `Menu`/`Form`), so
/// the golden uses `ProfileListSnapshotContent` — a hand-built header + row stack
/// over the canvas — the established native-control stand-in pattern.
public struct ProfileListView: View {
    let profiles: [ProfileStat]
    @Binding var selection: String?

    public init(profiles: [ProfileStat], selection: Binding<String?>) {
        self.profiles = profiles
        self._selection = selection
    }

    /// Alive-first, matching the grid + sidebar order.
    private var ordered: [ProfileStat] { sortProfiles(profiles) }

    public var body: some View {
        Table(ordered, selection: $selection) {
            TableColumn("Profile") { stat in
                HStack(spacing: Theme.Space.sm) {
                    StatusDot(running: stat.running, size: 7)
                    BadgeDisc(stat: stat, size: 18)
                    Text(stat.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                .accessibilityIdentifier("list-row-\(stat.effSlug)")
            }
            .width(min: 180, ideal: 220)

            TableColumn("Status") { stat in
                Text(stat.running ? "Running" : "Stopped")
                    .font(.system(size: 12))
                    .foregroundStyle(stat.running ? Theme.mint : Theme.text3)
            }
            .width(min: 70, ideal: 84)

            TableColumn("CPU") { stat in
                Text(stat.running ? formatCPU(stat.cpu) : "—")
                    .font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(Theme.text2)
            }
            .width(min: 56, ideal: 64)

            TableColumn("Memory") { stat in
                Text(stat.running ? formatMemoryMB(stat.mem) : "—")
                    .font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(Theme.text2)
            }
            .width(min: 72, ideal: 88)

            TableColumn("Terminals") { stat in
                Text(stat.running ? "\(stat.ptys)" : "—")
                    .font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(Theme.text2)
            }
            .width(min: 64, ideal: 76)

            TableColumn("Handles") { stat in
                // The default instance never leak-alerts in UI; still show its pool.
                Text(stat.running ? "\(stat.ptmx)/\(stat.ptmxMax)" : "—")
                    .font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(Theme.text2)
            }
            .width(min: 72, ideal: 88)
        }
        .accessibilityIdentifier("profile-table")
        .background(Theme.canvas)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Snapshot stand-in

/// Deterministic stand-in for `ProfileListView` — a header row + one row per
/// profile over the canvas, mirroring the `Table`'s columns. Native `Table`
/// renders empty under `ImageRenderer`, so the golden uses this hand-built layout.
public struct ProfileListSnapshotContent: View {
    let profiles: [ProfileStat]
    let selection: String?

    public init(profiles: [ProfileStat], selection: String? = nil) {
        self.profiles = profiles
        self.selection = selection
    }

    private var ordered: [ProfileStat] { sortProfiles(profiles) }

    // Column widths mirror the Table's ideals so the stand-in reads true.
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
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            VStack(spacing: 1) {
                ForEach(ordered) { stat in
                    row(stat)
                    if stat.id != ordered.last?.id {
                        Divider().overlay(Theme.hairline).padding(.horizontal, Theme.Space.md)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas)
    }
}
