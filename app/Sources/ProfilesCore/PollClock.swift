import Foundation

/// The 2s poll interval, injectable so tests run instantly and deterministically.
public protocol PollClock: Sendable { func sleepTick() async }

public struct RealClock: PollClock {
    public init() {}
    public func sleepTick() async { try? await Task.sleep(nanoseconds: 2_000_000_000) }
}

public struct ImmediateClock: PollClock {
    public init() {}
    public func sleepTick() async {}
}
