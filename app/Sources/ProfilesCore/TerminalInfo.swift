import Foundation

/// One terminal (pty) held by an instance's process tree, as emitted by
/// `engine.sh cmd_terminals`: `[{dev,pid,cmd,idle}]`. `dev` is a `/dev/ttysNN`
/// device path (the dedup key — one row per device), `cmd` the holding process's
/// command, `idle` the seconds since the tty's mtime (`-1` when unknown). The view
/// formats idle into "active"/"Nm idle"/"—".
public struct TerminalInfo: Codable, Identifiable, Sendable, Equatable {
    public let dev: String
    public let pid: Int
    public let cmd: String
    public let idle: Int

    public init(dev: String, pid: Int, cmd: String, idle: Int) {
        self.dev = dev
        self.pid = pid
        self.cmd = cmd
        self.idle = idle
    }

    /// Identity is the device path — `closeterm` targets the device, and the engine
    /// already dedupes to one row per `/dev/ttysNN`.
    public var id: String { dev }

    public static func decodeList(from data: Data) throws -> [TerminalInfo] {
        try JSONDecoder().decode([TerminalInfo].self, from: data)
    }
}
