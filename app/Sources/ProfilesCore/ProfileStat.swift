import Foundation

public struct ProfileStat: Codable, Identifiable, Sendable, Equatable {
    public let name: String
    public let slug: String
    public let running: Bool
    public let cpu: Double
    public let mem: Double
    public let procs: Int
    public let ptys: Int
    public let ptmx: Int
    public let ptmxMax: Int
    public let disk: Int
    public let opens: Int
    public let last: String
    public let color: String
    public let remote: Bool

    public init(name: String, slug: String, running: Bool, cpu: Double, mem: Double,
                procs: Int, ptys: Int, ptmx: Int, ptmxMax: Int, disk: Int, opens: Int,
                last: String, color: String, remote: Bool) {
        self.name = name; self.slug = slug; self.running = running
        self.cpu = cpu; self.mem = mem; self.procs = procs; self.ptys = ptys
        self.ptmx = ptmx; self.ptmxMax = ptmxMax; self.disk = disk; self.opens = opens
        self.last = last; self.color = color; self.remote = remote
    }

    public var isDefault: Bool { slug.isEmpty }
    /// The slug the engine expects for actions ("default" for the empty-slug default instance).
    public var effSlug: String { slug.isEmpty ? "default" : slug }
    public var id: String { effSlug }

    public static func decodeList(from data: Data) throws -> [ProfileStat] {
        try JSONDecoder().decode([ProfileStat].self, from: data)
    }
}
