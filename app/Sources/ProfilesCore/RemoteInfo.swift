import Foundation

/// The Remote-access info for a profile, as emitted by `engine.sh cmd_remoteinfo`:
/// `{"slug","session","user","host","tailscaleIp","alreadyRunning"}` on success, or
/// `{"error":"<msg>"}` when the prerequisites are missing (no `screen`, no `claude`
/// CLI, invalid id). The error path emits ONLY the `error` key, so every other field
/// decodes with a default — `error != nil` is the signal the sheet branches on.
public struct RemoteInfo: Codable, Equatable, Sendable {
    public let slug: String
    public let session: String
    public let user: String
    public let host: String
    public let tailscaleIp: String
    public let alreadyRunning: Bool
    /// Present only on the engine's failure path; nil on success.
    public let error: String?

    public init(slug: String, session: String, user: String, host: String,
                tailscaleIp: String, alreadyRunning: Bool, error: String? = nil) {
        self.slug = slug
        self.session = session
        self.user = user
        self.host = host
        self.tailscaleIp = tailscaleIp
        self.alreadyRunning = alreadyRunning
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case slug, session, user, host, tailscaleIp, alreadyRunning, error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Every success field defaults so the error-only `{"error":...}` JSON decodes.
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        session = try c.decodeIfPresent(String.self, forKey: .session) ?? ""
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        tailscaleIp = try c.decodeIfPresent(String.self, forKey: .tailscaleIp) ?? ""
        alreadyRunning = try c.decodeIfPresent(Bool.self, forKey: .alreadyRunning) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    public static func decode(from data: Data) throws -> RemoteInfo {
        try JSONDecoder().decode(RemoteInfo.self, from: data)
    }

    /// The local SSH attach command (`ssh <user>@<host> -t "screen -r <session>"`),
    /// the one the QR encodes and the first Copy block shows.
    public var localCommand: String {
        "ssh \(user)@\(host) -t \"screen -r \(session)\""
    }

    /// The any-network attach command over Tailscale, or nil when no Tailscale IP.
    public var tailscaleCommand: String? {
        guard !tailscaleIp.isEmpty else { return nil }
        return "ssh \(user)@\(tailscaleIp) -t \"screen -r \(session)\""
    }
}
