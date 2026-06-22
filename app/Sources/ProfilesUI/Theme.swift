import SwiftUI

/// Centralized "Calm Instrument" design tokens. The app is always dark; every
/// color here is an explicit constant (no system semantic colors except where
/// the spec calls for severity). Spec block is authoritative — see
/// docs/superpowers/specs/2026-06-22-swiftui-dashboard-design.md.
public enum Theme {
    // MARK: Surfaces (the depth ladder — depth comes from this + hairlines, never shadows)
    public static let canvas   = Color(hex: 0x16150F)
    public static let surface1 = Color(hex: 0x1F1E17)
    public static let surface2 = Color(hex: 0x262419)
    public static let surface3 = Color(hex: 0x2E2C1F)

    // MARK: Hairlines (depth lining)
    public static let hairline    = Color.white.opacity(0.06)
    public static let hairlineLit = Color.white.opacity(0.11)

    // MARK: Text ramp
    public static let text  = Color(hex: 0xF1EFE8)             // 100%
    public static let text2 = Color(hex: 0xF1EFE8).opacity(0.62)
    public static let text3 = Color(hex: 0xF1EFE8).opacity(0.40)
    public static let text4 = Color(hex: 0xF1EFE8).opacity(0.28)

    // MARK: Semantic (disciplined)
    public static let mint  = Color(hex: 0x5DCAA5)   // live/running ONLY
    public static let coral = Color(hex: 0xD85A30)   // brand + focus ring + critical
    public static let amber = Color(hex: 0xE0A333)   // warning

    // MARK: Metric identity (separate from severity)
    public static let cpuLine = Color(hex: 0xE08A5E)
    public static let memLine = Color(hex: 0x4FA8A0)
    public static let leakHot = Color(hex: 0xF0997B) // leak tail past threshold

    // MARK: Spacing scale (4 · 8 · 12 · 16 · 20 · 24 · 32)
    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let xxxl: CGFloat = 32
    }

    // MARK: Corner radii (pill 6 / button 8 / disc 10 / card 14 / modal 16)
    public enum Radius {
        public static let pill: CGFloat = 6
        public static let button: CGFloat = 8
        public static let disc: CGFloat = 10
        public static let card: CGFloat = 14
        public static let modal: CGFloat = 16
    }

    // MARK: Badge palette (matches engine.sh `badge_palette` order exactly)
    public static let badgePalette: [Color] = [
        Color(rgb: 59, 125, 216),   // 0 blue
        Color(rgb: 93, 202, 165),   // 1 mint
        Color(rgb: 224, 165, 94),   // 2 amber
        Color(rgb: 124, 92, 196),   // 3 purple
        Color(rgb: 210, 95, 140),   // 4 pink
        Color(rgb: 76, 169, 178),   // 5 teal
    ]

    public static func badgeColor(for index: Int) -> Color {
        let i = ((index % badgePalette.count) + badgePalette.count) % badgePalette.count
        return badgePalette[i]
    }

    /// Parse the engine's `color` field, which `profile_json` emits as `#RRGGBB`
    /// (e.g. the Dock-badge color, or `#6E6A62` for the default instance). If the
    /// string isn't a parseable hex, fall back to a deterministic slug-hash into
    /// the 6-color palette (matching the engine's `cksum % 6` intent loosely —
    /// the real hash differs but determinism per-slug is what matters in the UI).
    public static func badgeColor(forHex hex: String, slug: String = "") -> Color {
        if let c = Color(hexString: hex) { return c }
        return badgeColor(for: stableHash(slug) % badgePalette.count)
    }

    /// A platform-stable string hash (Swift's `String.hashValue` is salted per-run).
    static func stableHash(_ s: String) -> Int {
        var h = 5381
        for b in s.utf8 { h = ((h << 5) &+ h) &+ Int(b) }
        return abs(h)
    }
}

public extension Color {
    /// Build a Color from a 0xRRGGBB integer literal.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    init(rgb r: Int, _ g: Int, _ b: Int) {
        self.init(.sRGB, red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0, opacity: 1)
    }

    /// Parse a `#RRGGBB` (or `RRGGBB`) hex string; nil if malformed.
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}
