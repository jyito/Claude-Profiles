// Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
// See LICENSE and NOTICE in the repository root.
import CoreGraphics

/// Pure side-by-side layout math for the window stacker. Splits `bounds` (a
/// screen's visible frame in Cocoa y-up coordinates) into `count` equal tiles,
/// biased toward columns — the "stack side by side" ask:
///
///   1 → the full frame            4 → 2 × 2
///   2 → two columns               5–6 → 2 rows × 3 columns
///   3 → three columns             7–9 → 3 × 3 …
///
/// Frames come back row-major from the VISUAL top-left (Cocoa y-up: the first
/// row has the larger y). The caller converts to AX / Terminal top-left-origin
/// coordinates — this function stays coordinate-flip-free so it unit-tests as
/// plain geometry.
public func stackFrames(in bounds: CGRect, count: Int, gap: CGFloat = 10) -> [CGRect] {
    guard count > 0, bounds.width > 0, bounds.height > 0 else { return [] }
    let rows = count <= 3 ? 1 : Int(Double(count).squareRoot().rounded(.down))
    let cols = Int((Double(count) / Double(rows)).rounded(.up))
    let w = (bounds.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
    let h = (bounds.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
    var frames: [CGRect] = []
    frames.reserveCapacity(count)
    for i in 0..<count {
        let r = i / cols
        let c = i % cols
        let x = bounds.minX + CGFloat(c) * (w + gap)
        let y = bounds.maxY - h - CGFloat(r) * (h + gap)
        frames.append(CGRect(x: x, y: y, width: w, height: h))
    }
    return frames
}
