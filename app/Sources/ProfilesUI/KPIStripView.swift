import SwiftUI
import ProfilesCore

/// The fleet instrument strip — the ONLY place aggregates live (cards carry
/// per-instance only). A surface1 band of hairline-divided cells computed from
/// the profiles. All numbers monospacedDigit.
public struct KPIStripView: View {
    let profiles: [ProfileStat]

    public init(profiles: [ProfileStat]) {
        self.profiles = profiles
    }

    // MARK: Aggregates
    private var running: [ProfileStat] { profiles.filter { $0.running } }
    private var totalMem: Double { running.reduce(0) { $0 + $1.mem } }
    private var totalCPU: Double { running.reduce(0) { $0 + $1.cpu } }
    private var totalTerminals: Int { profiles.reduce(0) { $0 + $1.ptys } }
    private var runningCount: Int { running.count }
    private var totalCount: Int { profiles.count }

    /// Worst handle-pool ratio across the fleet (used/ceiling).
    private var worstHandle: (used: Int, max: Int, ratio: Double) {
        var best = (used: 0, max: 0, ratio: 0.0)
        for p in profiles {
            let r = p.ptmxMax > 0 ? Double(p.ptmx) / Double(p.ptmxMax) : 0
            if r >= best.ratio { best = (p.ptmx, p.ptmxMax, r) }
        }
        return best
    }

    private var handleBarColor: Color {
        let r = worstHandle.ratio
        if r >= 0.90 { return Theme.coral }
        if r >= 0.75 { return Theme.amber }
        return Theme.text3
    }

    public var body: some View {
        HStack(spacing: 0) {
            memoryCell
            divider
            countCell(eyebrow: "RUNNING",
                      value: "\(runningCount)/\(totalCount)",
                      tint: Theme.text)
            divider
            countCell(eyebrow: "TOTAL CPU",
                      value: formatCPU(totalCPU),
                      tint: Theme.text)
            divider
            countCell(eyebrow: "TERMINALS",
                      value: "\(totalTerminals)",
                      tint: Theme.text)
            divider
            handleCell
        }
        .padding(.vertical, Theme.Space.md)
        .padding(.horizontal, Theme.Space.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 40)
            .padding(.horizontal, Theme.Space.sm)
    }

    private func eyebrow(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.text3)
    }

    private var memoryCell: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            eyebrow("MEMORY IN USE")
            Text(formatMemoryMB(totalMem))
                .font(.title2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
            // teal micro-bar (always full — it's an identity accent, not a gauge)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.memLine)
                .frame(width: 48, height: 3)
            (Text("across ").foregroundColor(Theme.text3)
             + Text("\(runningCount)").foregroundColor(Theme.mint)
             + Text(" running").foregroundColor(Theme.text3))
                .font(.system(size: 11))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countCell(eyebrow eb: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            eyebrow(eb)
            Text(value)
                .font(.title2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var handleCell: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            eyebrow("HANDLE POOL")
            Text("\(worstHandle.used)/\(worstHandle.max)")
                .font(.title2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface3)
                    Capsule()
                        .fill(handleBarColor)
                        .frame(width: Swift.max(geo.size.width * Swift.min(worstHandle.ratio, 1), 2))
                }
            }
            .frame(width: 64, height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
