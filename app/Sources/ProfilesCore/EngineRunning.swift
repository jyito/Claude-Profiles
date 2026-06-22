import Foundation

public enum EngineError: Error, Equatable { case nonZeroExit(Int32) }

/// The seam between the app and engine.sh. EngineClient is the real impl; FixtureEngine is the test double.
public protocol EngineRunning: Sendable {
    func stats() async throws -> [ProfileStat]
    /// Run an arbitrary verb + args (e.g. `["clean","work","gpu"]`, `["setbadge","work","2"]`).
    func run(_ args: [String]) async throws
    /// Typed terminals drill-down for `slug` (`"default"` for the default instance).
    func terminals(_ slug: String) async throws -> [TerminalInfo]
}

public extension EngineRunning {
    /// Phase-2 convenience for the common single-arg verbs (`open`/`quit`/`focus`/…),
    /// delegating to the general `run([verb, slug])`. Keeps existing callers unchanged.
    func run(_ verb: String, _ slug: String) async throws {
        try await run([verb, slug])
    }
}
