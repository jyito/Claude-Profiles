import Foundation

/// Test double for EngineRunning — returns canned stats/terminals, or throws when `shouldThrow`.
public final class FixtureEngine: EngineRunning, @unchecked Sendable {
    public var stats: [ProfileStat]
    public var terminalsList: [TerminalInfo] = []
    public var shouldThrow = false
    public private(set) var ranArgs: [[String]] = []
    /// Canned config returned by `getConfig`; tests mutate it to assert decode/load.
    public var config = ProfileConfig()
    /// Records `(key, value)` for every `setConfig` so tests can assert the routed pair.
    public private(set) var setConfigCalls: [(String, Int)] = []
    /// The slug `create` returns; tests set this to assert the parsed result flows through.
    public var createSlug = "newprofile"
    /// Records each `create(name)` argument.
    public private(set) var createNames: [String] = []
    public init(stats: [ProfileStat]) { self.stats = stats }

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
    public func getConfig() async throws -> ProfileConfig {
        if shouldThrow { throw EngineError.nonZeroExit(1) }
        return config
    }
    public func setConfig(_ key: String, _ value: Int) async throws {
        if shouldThrow { throw EngineError.nonZeroExit(1) }
        setConfigCalls.append((key, value))
    }
    public func create(_ name: String) async throws -> String {
        if shouldThrow { throw EngineError.nonZeroExit(1) }
        createNames.append(name)
        return createSlug
    }
}
