import SwiftUI
import ProfilesCore

/// The per-profile identity avatar: a rounded square in the profile's badge color
/// with the profile's initial in near-black. The default instance shows a `lock`
/// instead of an initial (its restricted-contract tell).
public struct BadgeDisc: View {
    let name: String
    let colorHex: String
    let slug: String
    let size: CGFloat
    let isDefault: Bool

    public init(name: String, colorHex: String, slug: String = "", size: CGFloat = 34, isDefault: Bool = false) {
        self.name = name
        self.colorHex = colorHex
        self.slug = slug
        self.size = size
        self.isDefault = isDefault
    }

    public init(stat: ProfileStat, size: CGFloat = 34) {
        self.init(name: stat.name, colorHex: stat.color, slug: stat.slug, size: size, isDefault: stat.isDefault)
    }

    /// First letter of the name with a leading "Claude " stripped, uppercased.
    static func initial(for name: String) -> String {
        var n = name
        if n.hasPrefix("Claude ") { n.removeFirst("Claude ".count) }
        let c = n.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "C"
        return c.isEmpty ? "C" : c
    }

    private var fill: Color { Theme.badgeColor(forHex: colorHex, slug: slug) }

    public var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.disc * (size / 34), style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                if isDefault {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.8))
                } else {
                    Text(Self.initial(for: name))
                        .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.8))
                }
            }
            .accessibilityHidden(true)
    }
}
