import SwiftUI
import ProfilesCore

/// One sidebar row: status dot + small badge disc + name + trailing MEM (running).
public struct SidebarRow: View {
    let stat: ProfileStat

    public init(stat: ProfileStat) { self.stat = stat }

    public var body: some View {
        HStack(spacing: Theme.Space.sm) {
            StatusDot(running: stat.running, size: 8)
            BadgeDisc(stat: stat, size: 18)
            Text(stat.name)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.sm)
            if stat.running {
                Text(formatMemoryMB(stat.mem))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text3)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("sidebar-row-\(stat.effSlug)")
    }
}

/// The vibrant profile list. Sections "Profiles" (non-default, alive-first) +
/// "System" (the default row). Selection drives the detail/inspector.
///
/// Hand-built (a `ScrollView` of section headers + tappable `SidebarRow`s) rather
/// than a native `List(.sidebar)`: the native List renders EMPTY under
/// `ImageRenderer` (the snapshot harness), so it was never visually verified and
/// shipped blank in the live app. This layout renders headlessly AND interactively,
/// so the golden tests the real view. The scene keeps the `.background(VisualEffectView())`
/// vibrancy around this content.
public struct SidebarView: View {
    let profiles: [ProfileStat]
    @Binding var selection: String?

    public init(profiles: [ProfileStat], selection: Binding<String?>) {
        self.profiles = profiles
        self._selection = selection
    }

    private var accounts: [ProfileStat] {
        sortProfiles(profiles.filter { !$0.isDefault })
    }
    private var system: [ProfileStat] {
        profiles.filter { $0.isDefault }
    }

    private func header(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(Theme.text3)
            .padding(.top, Theme.Space.sm)
            .padding(.horizontal, Theme.Space.xs)
    }

    @Environment(\.snapshotMode) private var snapshotMode

    private func row(_ stat: ProfileStat) -> some View {
        let isSel = selection == stat.effSlug
        return SidebarRow(stat: stat)
            .padding(.horizontal, Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(isSel ? Theme.coral.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { selection = stat.effSlug }
            .pointerCursor()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            header("PROFILES")
            ForEach(accounts) { row($0) }
            header("SYSTEM")
            ForEach(system) { row($0) }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    public var body: some View {
        // `ImageRenderer` (the snapshot harness) proposes a nil height into a
        // `ScrollView`, collapsing its content to empty — the very blank-sidebar bug
        // we're fixing. So render the rows directly under the snapshot, and only
        // wrap them in a live `ScrollView` for the real, scrollable app.
        Group {
            if snapshotMode {
                content
            } else {
                ScrollView {
                    content
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
