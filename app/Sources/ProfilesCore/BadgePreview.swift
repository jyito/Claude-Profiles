import Foundation

/// Mirrors `engine.sh`'s identity derivation so the New Profile sheet can preview
/// the exact slug + badge color a name will get BEFORE the wrapper is created:
///
///  - `slugify` mirrors `cmd_create`: lowercase, then keep only `[a-z0-9]`.
///  - `badgeColorIndex(forSlug:)` ports `badge_color_for` = POSIX `cksum(slug) % 6`.
///    The CRC is the exact POSIX `cksum` algorithm (CRC-32/CKSUM: poly 0x04C11DB7,
///    init 0, no input/output reflection, the byte length appended, final XOR
///    0xFFFFFFFF) so the preview index equals the real Dock-badge assignment.
///  - `initial(forName:)` mirrors `badge_icon`: strip a leading "Claude ",
///    uppercase the first character.
public enum BadgePreview {

    // MARK: Slug

    /// Lowercase the name, then keep only ASCII letters/digits — exactly
    /// `cmd_create`'s `tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'`.
    public static func slugify(_ name: String) -> String {
        var out = ""
        for scalar in name.lowercased().unicodeScalars {
            let v = scalar.value
            let isDigit = v >= 48 && v <= 57      // 0-9
            let isLower = v >= 97 && v <= 122     // a-z
            if isDigit || isLower { out.unicodeScalars.append(scalar) }
        }
        return out
    }

    // MARK: Initial

    /// First letter of the name with a leading "Claude " stripped, uppercased;
    /// "C" when empty (matches the engine's `[ -n "$letter" ] || letter="C"`).
    public static func initial(forName name: String) -> String {
        var n = name
        if n.hasPrefix("Claude ") { n.removeFirst("Claude ".count) }
        let first = n.trimmingCharacters(in: .whitespaces).first
        guard let first else { return "C" }
        let c = String(first).uppercased()
        return c.isEmpty ? "C" : c
    }

    // MARK: Badge color index (POSIX cksum % 6)

    /// The deterministic default palette index for a slug, matching
    /// `engine.sh badge_index_for` (sans user override, which the engine layers on).
    /// Returns 0–5 indexing `Theme.badgePalette` / `badge_palette`.
    public static func badgeColorIndex(forSlug slug: String) -> Int {
        Int(cksum(Array(slug.utf8)) % 6)
    }

    // MARK: POSIX cksum

    // CRC-32/CKSUM lookup table (poly 0x04C11DB7, MSB-first), built once.
    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i) << 24
            for _ in 0..<8 {
                if crc & 0x8000_0000 != 0 {
                    crc = (crc << 1) ^ 0x04C1_1DB7
                } else {
                    crc <<= 1
                }
            }
            table[i] = crc
        }
        return table
    }()

    /// The POSIX `cksum` CRC of a byte sequence. The standard feeds every input
    /// byte, then the file length encoded as bytes (least-significant first,
    /// dropping the run of trailing zero bytes), then inverts.
    public static func cksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0
        for b in bytes {
            crc = (crc << 8) ^ crcTable[Int(((crc >> 24) ^ UInt32(b)) & 0xFF)]
        }
        // Append the length, low byte first, stopping once it reaches zero.
        var len = bytes.count
        while len != 0 {
            let b = UInt8(len & 0xFF)
            crc = (crc << 8) ^ crcTable[Int(((crc >> 24) ^ UInt32(b)) & 0xFF)]
            len >>= 8
        }
        return ~crc
    }
}
