import Foundation

public struct EngineClient: EngineRunning {
    public let enginePath: String
    public init(enginePath: String) { self.enginePath = enginePath }

    private static func invoke(_ path: String, _ args: [String]) throws -> (Data, Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [path] + args
        let outPipe = Pipe()
        p.standardOutput = outPipe
        // stderr is intentionally discarded; route to /dev/null rather than an
        // undrained Pipe (an undrained stderr Pipe deadlocks waitUntilExit() once
        // the child writes past the ~64KB pipe buffer — nobody reads it back).
        p.standardError = FileHandle.nullDevice
        try p.run()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (out, p.terminationStatus)
    }

    public func stats() async throws -> [ProfileStat] {
        let path = enginePath
        return try await Task.detached(priority: .utility) {
            let (out, code) = try Self.invoke(path, ["stats"])
            if code != 0 { throw EngineError.nonZeroExit(code) }
            return try ProfileStat.decodeList(from: out)
        }.value
    }

    public func run(_ args: [String]) async throws {
        let path = enginePath
        try await Task.detached(priority: .utility) {
            let (out, code) = try Self.invoke(path, args)
            if code != 0 { throw EngineError.nonZeroExit(code) }
            // engine.sh action verbs exit 0 even on failure, printing an error
            // token to stdout (`err <msg>` / `refused` / `baddev`). Surface those
            // as a thrown error so a failed action never reports success.
            let stdout = String(data: out, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if stdout == "refused" || stdout == "baddev" || stdout.hasPrefix("err") {
                throw EngineError.actionFailed(stdout)
            }
        }.value
    }

    public func terminals(_ slug: String) async throws -> [TerminalInfo] {
        let path = enginePath
        return try await Task.detached(priority: .utility) {
            let (out, code) = try Self.invoke(path, ["terminals", slug])
            if code != 0 { throw EngineError.nonZeroExit(code) }
            return try TerminalInfo.decodeList(from: out)
        }.value
    }

    public func getConfig() async throws -> ProfileConfig {
        let path = enginePath
        return try await Task.detached(priority: .utility) {
            let (out, code) = try Self.invoke(path, ["getconfig"])
            if code != 0 { throw EngineError.nonZeroExit(code) }
            return try ProfileConfig.decode(from: out)
        }.value
    }

    public func setConfig(_ key: String, _ value: Int) async throws {
        // `setconfig` exits 0 even on `err badkey`/`err badval`; `run` already
        // surfaces those error tokens as a thrown `actionFailed`.
        try await run(["setconfig", key, String(value)])
    }

    public func create(_ name: String) async throws -> String {
        let path = enginePath
        return try await Task.detached(priority: .utility) {
            let (out, code) = try Self.invoke(path, ["create", name])
            if code != 0 { throw EngineError.nonZeroExit(code) }
            // `create` prints `ok <slug>` on success or `err <msg>` on failure — both
            // exit 0, so the slug must be parsed from stdout (the generic `run` would
            // discard it). Surface `err` as a thrown error.
            let stdout = String(data: out, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if stdout.hasPrefix("ok ") {
                let slug = String(stdout.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !slug.isEmpty { return slug }
            }
            throw EngineError.actionFailed(stdout.isEmpty ? "err empty create response" : stdout)
        }.value
    }
}
