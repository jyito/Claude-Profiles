import Foundation

/// Test double for EngineRunning — returns canned stats, or throws when `shouldThrow`.
public final class FixtureEngine: EngineRunning, @unchecked Sendable {
    public var stats: [ProfileStat]
    public var shouldThrow = false
    public private(set) var ranVerbs: [(String, String)] = []
    public init(stats: [ProfileStat]) { self.stats = stats }

    public func stats() async throws -> [ProfileStat] {
        if shouldThrow { throw EngineError.nonZeroExit(1) }
        return stats
    }
    public func run(_ verb: String, _ slug: String) async throws {
        if shouldThrow { throw EngineError.nonZeroExit(1) }
        ranVerbs.append((verb, slug))
    }
}
