import Foundation

public enum EngineError: Error, Equatable { case nonZeroExit(Int32) }

/// The seam between the app and engine.sh. EngineClient is the real impl; FixtureEngine is the test double.
public protocol EngineRunning: Sendable {
    func stats() async throws -> [ProfileStat]
    func run(_ verb: String, _ slug: String) async throws
}
