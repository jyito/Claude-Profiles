import Foundation

/// Test double for EngineRunning — returns canned stats/terminals, or throws when `shouldThrow`.
public final class FixtureEngine: EngineRunning, @unchecked Sendable {
    public var stats: [ProfileStat]
    public var terminalsList: [TerminalInfo] = []
    public var shouldThrow = false
    public private(set) var ranArgs: [[String]] = []
    public init(stats: [ProfileStat]) { self.stats = stats }

    /// Derived view for the common two-arg verbs: `[verb, slug]` rows of `ranArgs`.
    public var ranVerbs: [(String, String)] {
        ranArgs.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
    }

    public func stats() async throws -> [ProfileStat] {
        if shouldThrow { throw EngineError.nonZeroExit(1) }
        return stats
    }
    public func run(_ args: [String]) async throws {
        if shouldThrow { throw EngineError.nonZeroExit(1) }
        ranArgs.append(args)
    }
    public func terminals(_ slug: String) async throws -> [TerminalInfo] {
        if shouldThrow { throw EngineError.nonZeroExit(1) }
        return terminalsList
    }
}
