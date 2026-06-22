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

    public func run(_ verb: String, _ slug: String) async throws {
        let path = enginePath
        try await Task.detached(priority: .utility) {
            let (_, code) = try Self.invoke(path, [verb, slug])
            if code != 0 { throw EngineError.nonZeroExit(code) }
        }.value
    }
}
