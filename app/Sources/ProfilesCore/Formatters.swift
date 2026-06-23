import Foundation

private let grouping: NumberFormatter = {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US_POSIX")
    // POSIX locale + .decimal does not emit a thousands separator on its own;
    // force it so grouped numbers are deterministic ("2,230") regardless of host locale.
    f.usesGroupingSeparator = true; f.groupingSeparator = ","; f.groupingSize = 3
    f.maximumFractionDigits = 0; return f
}()

private func grouped(_ n: Int) -> String { grouping.string(from: NSNumber(value: n)) ?? "\(n)" }

/// Memory is MB from the engine. < 4 GB → "N MB" (grouped); ≥ 4 GB → "X.Y GB".
/// (Higher GB cutoff than disk so typical multi-GB instances stay readable in MB —
///  matches the locked FormatterTests: 2,230 MB stays MB, 8,400 MB → 8.2 GB.)
public func formatMemoryMB(_ mb: Double) -> String {
    let m = Int(mb.rounded())
    if m < 4096 { return "\(grouped(m)) MB" }
    return String(format: "%.1f GB", mb / 1024.0)
}

/// CPU is a summed percentage that can exceed 100 (per-core). Never clamp.
public func formatCPU(_ pct: Double) -> String {
    if pct == pct.rounded() { return "\(Int(pct))%" }
    return String(format: "%.1f%%", pct)
}

/// Disk is MB; -1 is the default-instance sentinel (off-limits → not shown).
public func formatDiskMB(_ mb: Int) -> String {
    if mb < 0 { return "—" }
    if mb < 1024 { return "\(grouped(mb)) MB" }
    return String(format: "%.1f GB", Double(mb) / 1024.0)
}

/// Per-tile handle readout: just the count + "handles". The ceiling (`max`) is
/// deliberately NOT shown here — it already lives in the KPI strip ("HANDLE POOL
/// N/ceiling") and the detail page's handle-pool chart (dashed ceiling rule), so
/// repeating "/ 511" on every card was redundant and inconsistent with the default
/// card's "N handles". `max` is kept in the signature so callers don't restructure.
public func formatHandles(used: Int, max: Int) -> String {
    "\(used) handles"
}
