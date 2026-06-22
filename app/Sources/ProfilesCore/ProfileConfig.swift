import Foundation

/// The two opt-in automation knobs (CLAUDE.md: both default 0 = disabled), as
/// emitted by `engine.sh cmd_getconfig`:
/// `{"autoCloseIdleMin":N,"autoCleanThresholdMB":N,"autoRestartLeakAt":N}`.
/// All three are non-negative integers; `0` means the rule is off.
public struct ProfileConfig: Codable, Equatable, Sendable {
    /// Auto-clean a stopped profile once its data dir exceeds this many MB (0 = off).
    public var autoCleanThresholdMB: Int
    /// Auto-close a terminal idle past this many minutes (0 = off).
    public var autoCloseIdleMin: Int
    /// Auto-restart a profile leaking at least this many `/dev/ptmx` handles (0 = off).
    public var autoRestartLeakAt: Int

    public init(autoCleanThresholdMB: Int = 0, autoCloseIdleMin: Int = 0, autoRestartLeakAt: Int = 0) {
        self.autoCleanThresholdMB = autoCleanThresholdMB
        self.autoCloseIdleMin = autoCloseIdleMin
        self.autoRestartLeakAt = autoRestartLeakAt
    }

    public static func decode(from data: Data) throws -> ProfileConfig {
        try JSONDecoder().decode(ProfileConfig.self, from: data)
    }

    /// The three `setconfig` keys, paired with the `ProfileConfig` field each reads.
    /// Used by the Settings sheet so a changed picker routes the right key/value to
    /// the engine, and to read the current value back for the picker's selection.
    public enum Key: String, CaseIterable, Sendable {
        case autoCleanThresholdMB
        case autoCloseIdleMin
        case autoRestartLeakAt
    }

    public func value(for key: Key) -> Int {
        switch key {
        case .autoCleanThresholdMB: return autoCleanThresholdMB
        case .autoCloseIdleMin: return autoCloseIdleMin
        case .autoRestartLeakAt: return autoRestartLeakAt
        }
    }
}
