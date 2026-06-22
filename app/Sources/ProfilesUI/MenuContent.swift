import SwiftUI
import ProfilesCore

/// The menu-bar switcher's row content, factored out so the live `MenuBarExtra`
/// and the `menu-content` golden share one layout. Native `MenuBarExtra` menu
/// items render empty under `ImageRenderer` (same as `Menu`/`Table`), so the
/// snapshot uses `MenuContentSnapshot` — a hand-built row stack over a solid
/// surface — rather than the live menu chrome.
///
/// One row = a badge-color swatch + the profile name + a trailing mint dot when
/// running. Alive-first ordering (the default instance pinned, then running, then
/// stopped) matches the sidebar and the window grid.

/// A single switcher row's visual (swatch · name · running dot). Used only by the
/// snapshot stand-in; the live menu uses native menu items (see ProfilesApp).
public struct MenuSwitcherRow: View {
    let stat: ProfileStat

    public init(stat: ProfileStat) { self.stat = stat }

    public var body: some View {
        HStack(spacing: Theme.Space.sm) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.badgeColor(forHex: stat.color, slug: stat.slug))
                .frame(width: 12, height: 12)
            Text(stat.name)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.lg)
            if stat.running {
                Circle()
                    .fill(Theme.mint)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Theme.Space.sm)
        .accessibilityIdentifier("menu-row-\(stat.effSlug)")
    }
}

/// Deterministic stand-in for the menu-bar switcher's content — the row stack plus
/// the trailing New Profile / Quit actions, over a solid surface. NOT the live
/// `MenuBarExtra` menu (that renders empty headless). Snapshot-only.
public struct MenuContentSnapshot: View {
    let profiles: [ProfileStat]

    public init(profiles: [ProfileStat]) { self.profiles = profiles }

    /// Alive-first, matching the live menu's `sortProfiles` order.
    private var ordered: [ProfileStat] { sortProfiles(profiles) }

    private func footerRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text3)
                .frame(width: 12)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Theme.Space.sm)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(ordered) { MenuSwitcherRow(stat: $0) }
            Divider().overlay(Theme.hairline).padding(.vertical, Theme.Space.xs)
            footerRow("New Profile", systemImage: "plus")
            footerRow("Quit", systemImage: "power")
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface1)
    }
}
