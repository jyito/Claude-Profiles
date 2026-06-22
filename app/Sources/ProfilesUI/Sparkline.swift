import SwiftUI
import Charts

/// A chrome-less rolling sparkline: a line + gradient area to clear + a single
/// live-edge point on the last sample. Y is pinned to `0...max` so per-core CPU
/// over 100% never flattens. The `ghosted` variant (gray, no fill, no point) is
/// for stopped cards.
public struct Sparkline: View {
    let values: [Double]
    let tint: Color
    let filled: Bool
    let showPoint: Bool

    public init(values: [Double], tint: Color, filled: Bool = true, showPoint: Bool = true) {
        self.values = values
        self.tint = tint
        self.filled = filled
        self.showPoint = showPoint
    }

    /// Stopped-card variant: a faint gray trace with no fill and no live point.
    public static func ghosted(_ values: [Double]) -> Sparkline {
        Sparkline(values: values, tint: Theme.text.opacity(0.25), filled: false, showPoint: false)
    }

    private var yMax: Double { max(values.max() ?? 1, 1) }

    public var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", v))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)

                if filled {
                    AreaMark(x: .value("i", i), y: .value("v", v))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            .linearGradient(
                                colors: [tint.opacity(0.28), tint.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
            }
            if showPoint, let last = values.indices.last {
                PointMark(x: .value("i", last), y: .value("v", values[last]))
                    .symbol(.circle)
                    .symbolSize(28)
                    .foregroundStyle(tint)
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}
