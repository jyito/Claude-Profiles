import Foundation

public enum AlertState: Equatable, Sendable {
    case calm
    case warning(climbing: Bool)
    case critical
}

public struct PtmxSample: Sendable {
    public let used: Int
    public let max: Int
    public init(used: Int, max: Int) { self.used = used; self.max = max }
    public var ratio: Double { max > 0 ? Double(used) / Double(max) : 0 }
}

/// Sustained-breach + hysteresis severity. Thresholds:
/// warn ≥ 0.75 · critical-enter ≥ 0.90 sustained for `sustain` ticks · critical-exit < 0.80.
public struct PtmxHysteresis: Sendable {
    public static let warn = 0.75
    public static let high = 0.90
    public static let low  = 0.80
    public static let sustain = 3

    private var breachStreak = 0
    private var prevRatio = 0.0
    private var isCritical = false

    public init() {}

    public mutating func ingest(_ sample: PtmxSample) -> AlertState {
        let r = sample.ratio
        let climbing = r > prevRatio
        defer { prevRatio = r }

        breachStreak = (r >= Self.high) ? breachStreak + 1 : 0

        if isCritical {
            if r < Self.low { isCritical = false } else { return .critical }
        } else if breachStreak >= Self.sustain {
            isCritical = true
            return .critical
        }

        if r >= Self.warn { return .warning(climbing: climbing) }
        return .calm
    }
}
