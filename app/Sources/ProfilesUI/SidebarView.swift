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

    public var body: some View {
        List(selection: $selection) {
            Section("Profiles") {
                ForEach(accounts) { stat in
                    SidebarRow(stat: stat).tag(stat.effSlug)
                }
            }
            Section("System") {
                ForEach(system) { stat in
                    SidebarRow(stat: stat).tag(stat.effSlug)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

/// The static (deterministic) content used for snapshots — the row stack over a
/// solid canvas color, with section headers, NOT the live `List`/material.
public struct SidebarSnapshotContent: View {
    let profiles: [ProfileStat]

    public init(profiles: [ProfileStat]) { self.profiles = profiles }

    private var accounts: [ProfileStat] { sortProfiles(profiles.filter { !$0.isDefault }) }
    private var system: [ProfileStat] { profiles.filter { $0.isDefault } }

    private func header(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(Theme.text3)
            .padding(.top, Theme.Space.sm)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            header("PROFILES")
            ForEach(accounts) { SidebarRow(stat: $0) }
            header("SYSTEM")
            ForEach(system) { SidebarRow(stat: $0) }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas)
    }
}
