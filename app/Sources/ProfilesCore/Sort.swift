import Foundation

/// Alive-first ordering: the default instance pinned first, then running profiles,
/// then stopped — each group ordered case-insensitively by name (stable).
public func sortProfiles(_ profiles: [ProfileStat]) -> [ProfileStat] {
    func rank(_ p: ProfileStat) -> Int {
        if p.isDefault { return 0 }
        return p.running ? 1 : 2
    }
    return profiles.sorted { a, b in
        let ra = rank(a), rb = rank(b)
        if ra != rb { return ra < rb }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}
