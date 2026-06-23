import Foundation

public enum EngineError: Error, Equatable {
    case nonZeroExit(Int32)
    /// An action verb exited 0 but printed an engine error token (`err <msg>` /
    /// `refused` / `baddev`) — engine.sh reports action failures on stdout, not via
    /// the exit code, so these must be detected explicitly. Payload is the token.
    case actionFailed(String)
}

/// The seam between the app and engine.sh. EngineClient is the real impl; FixtureEngine is the test double.
public protocol EngineRunning: Sendable {
    func stats() async throws -> [ProfileStat]
    /// Run an arbitrary verb + args (e.g. `["clean","work","gpu"]`, `["setbadge","work","2"]`).
    func run(_ args: [String]) async throws
    /// Typed terminals drill-down for `slug` (`"default"` for the default instance).
    func terminals(_ slug: String) async throws -> [TerminalInfo]
    /// Decode `getconfig` into the two opt-in automation knobs.
    func getConfig() async throws -> ProfileConfig
    /// Persist one config key (`setconfig <key> <int>`); throws on the engine's `err` token.
    func setConfig(_ key: String, _ value: Int) async throws
    /// Create a profile wrapper for `name`. The engine prints `ok <slug>`; the slug
    /// is parsed and returned (the derived slug differs from the raw name). Throws
    /// `actionFailed` on the engine's `err <msg>` token.
    func create(_ name: String) async throws -> String
    /// Start/reuse a profile's Claude Code `screen` session and decode the connect
    /// info (`remoteinfo <slug>`). The engine reports a failure inside the JSON
    /// (`error` key), not via exit/token, so this returns `RemoteInfo` rather than
    /// throwing on a missing prerequisite.
    func remoteInfo(_ slug: String) async throws -> RemoteInfo
    /// Stop a profile's Claude Code `screen` session (`remotestop <slug>` →
    /// `screen -S claude-<slug> -X quit`). Idempotent; the engine always prints
    /// `ok`. Throws on the engine's `err`/`refused` tokens like other actions.
    func remoteStop(_ slug: String) async throws
    /// Put text on the clipboard (`copy <text>` → `pbcopy`) for the Remote sheet's Copy buttons.
    func copy(_ text: String) async throws
    /// Resolve an instance's main process PID for in-process focus (`mainpid <slug>`,
    /// or `defaultpid` when `slug == "default"`). Stdout is a single PID or empty;
    /// empty (not running) → `nil`. No error-token handling — the engine never
    /// prints one here. The PID, never the bundle id, is the focus target (all
    /// instances share Claude's bundle id).
    func mainPid(_ slug: String) async throws -> Int32?
}

public extension EngineRunning {
    /// Phase-2 convenience for the common single-arg verbs (`open`/`quit`/`focus`/…),
    /// delegating to the general `run([verb, slug])`. Keeps existing callers unchanged.
    func run(_ verb: String, _ slug: String) async throws {
        try await run([verb, slug])
    }
}
