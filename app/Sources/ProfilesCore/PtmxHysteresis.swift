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
/// Hysteresis: once `.leaking`, it stays leaking through small downward wobble and only
/// clears to `.calm` when the handles are actually freed — `used` falls back to/below
/// `floor + margin` (drained toward the low-water mark) OR `used <= terminals` (parity
/// restored, e.g. after a restart). This avoids amber flicker on a 1-handle jitter.
///
/// The ceiling (`kern.tty.ptmx_max`) no longer participates in the color decision; it
/// survives only on `PtmxSample` for the detail page's dashed ceiling rule.
public struct PtmxHysteresis: Sendable {
    /// A climb of this many handles above the floor (with excess) trips the leak.
    public static let climbDelta = 2
    /// Hysteresis clear band: leaking clears once `used` drains to within this of the
    /// floor (handles freed). 1 keeps a single-handle wobble from clearing prematurely.
    public static let margin = 1

    /// Running minimum of `used` — the baseline a climb is measured from. Re-bases
    /// downward on any new low so a later climb is read from the fresh floor, not a
    /// stale historic high. `nil` until the first sample seeds it.
    private var floor: Int?
    private var isLeaking = false

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
            }
        } else if excess && climbing {
            isLeaking = true
        }

        return isLeaking ? .leaking : .calm
    }
}
