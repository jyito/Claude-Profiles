import Foundation

/// The leak verdict. Two states only — there is no "critical" tier anymore: a leak
/// is a leak, shown in amber, regardless of how close the system pool is to its
/// ceiling. (The old `.warning(climbing:)`/`.critical` ceiling-gated tiers meant a
/// real 20–150-handle leak sat in calm gray until it threatened to wedge the whole
/// Mac — invisible exactly when it mattered. Now ANY active leak reads amber.)
public enum AlertState: Equatable, Sendable {
    case calm
    case leaking
}

/// One leak sample: the held `/dev/ptmx` masters (`used`, NOT deduped — the leak
/// metric), the system ceiling (`max`, kept only so callers don't have to restructure
/// and for the detail chart's ceiling rule — it no longer gates color), and the count
/// of live `terminals` (deduped real ptys) the instance actually has open.
public struct PtmxSample: Sendable {
    public let used: Int
    public let max: Int
    public let terminals: Int
    public init(used: Int, max: Int, terminals: Int) {
        self.used = used
        self.max = max
        self.terminals = terminals
    }
    public var ratio: Double { max > 0 ? Double(used) / Double(max) : 0 }
}

/// Active-leak detector with hysteresis. An instance is **leaking** when BOTH hold:
///
///   1. **excess** — `used > terminals`: it's holding more `/dev/ptmx` masters than it
///      has live terminals, i.e. masters that should have been freed when terminals
///      closed (the node-pty bug). Opening N terminals legitimately holds N masters, so
///      `used == terminals` is never a leak, at any absolute level.
///   2. **climbing** — `used` has risen at least `climbDelta` above its recent floor
///      (the running minimum, which re-bases downward whenever `used` drops). A flat
///      excess (one stuck handle that never grows) isn't the signal; a *rising* pool is.
///
/// Sustain: the leak condition (excess + climbing) must hold for `sustainTicks`
/// CONSECUTIVE samples before the state flips to `.leaking`. At the 2s poll that's
/// ~6s of a genuinely rising, excess pool — enough to ride out brief churn (a terminal
/// opening and closing within a couple of ticks) and err toward calm. While the
/// condition holds but the streak hasn't reached the threshold the state stays `.calm`;
/// any tick that breaks the condition resets the streak to zero.
///
/// Hysteresis: once `.leaking`, it stays leaking through small downward wobble and only
/// clears to `.calm` when the handles are actually freed — `used` falls back to/below
/// `floor + margin` (drained toward the low-water mark) OR `used <= terminals` (parity
/// restored, e.g. after a restart). This avoids amber flicker on a 1-handle jitter. The
/// sustain streak resets on clear, so re-arming a leak needs a fresh run of ticks.
///
/// The ceiling (`kern.tty.ptmx_max`) no longer participates in the color decision; it
/// survives only on `PtmxSample` for the detail page's dashed ceiling rule.
public struct PtmxHysteresis: Sendable {
    /// A climb of this many handles above the floor (with excess) qualifies a tick.
    public static let climbDelta = 2
    /// Consecutive qualifying ticks the leak condition must hold before flipping to
    /// `.leaking` (~6s at the 2s poll). Errs toward calm on brief churn.
    public static let sustainTicks = 3
    /// Hysteresis clear band: leaking clears once `used` drains to within this of the
    /// floor (handles freed). 1 keeps a single-handle wobble from clearing prematurely.
    public static let margin = 1

    /// Running minimum of `used` — the baseline a climb is measured from. Re-bases
    /// downward on any new low so a later climb is read from the fresh floor, not a
    /// stale historic high. `nil` until the first sample seeds it.
    private var floor: Int?
    private var isLeaking = false
    /// Count of consecutive ticks the leak condition has held while not yet leaking.
    private var sustain = 0

    public init() {}

    public mutating func ingest(_ sample: PtmxSample) -> AlertState {
        let used = sample.used

        // Seed / re-base the floor (running min). A drop in `used` (handles freed,
        // restart, fewer terminals) lowers the floor so the next climb starts fresh.
        let base = Swift.min(floor ?? used, used)
        floor = base

        let excess = used > sample.terminals
        let climbing = used - base >= Self.climbDelta

        if isLeaking {
            // Clear only when handles are genuinely freed: drained back toward the
            // floor, or parity with live terminals restored.
            if used <= sample.terminals || used <= base + Self.margin {
                isLeaking = false
                sustain = 0
            }
        } else if excess && climbing {
            // Condition holds — count it. Flip only once the streak reaches the
            // sustain threshold (errs toward calm on brief churn).
            sustain += 1
            if sustain >= Self.sustainTicks {
                isLeaking = true
                sustain = 0
            }
        } else {
            // Condition broke this tick — reset the streak.
            sustain = 0
        }

        return isLeaking ? .leaking : .calm
    }
}
