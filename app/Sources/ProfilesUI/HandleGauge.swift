import SwiftUI
import ProfilesCore

/// The leaked-handle (ptmx) capacity gauge. Two always-on channels for the leak
/// verdict — color + glyph + number — so it survives grayscale / colorblindness:
/// calm reads gray with a `terminal` glyph and "N handles" (the count only — the
/// ceiling lives in the KPI strip + the detail chart, not on every tile); an active
/// leak reads amber with a warning triangle, "N leaked", and a "↑ climbing" tell. The
/// capacity bar still fills toward the ceiling (amber when leaking) — only the text
/// drops the "/ max". There is no coral/critical tier — any active leak is amber,
/// regardless of ceiling.
public struct HandleGauge: View {
    let used: Int
    let max: Int
    let state: AlertState

    @Environment(\.snapshotMode) private var snapshotMode

    public init(used: Int, max: Int, state: AlertState) {
        self.used = used
        self.max = max
        self.state = state
    }

    private var ratio: Double { max > 0 ? Swift.min(Double(used) / Double(max), 1.0) : 0 }

    private var leaking: Bool { state == .leaking }

    private var barColor: Color { leaking ? Theme.amber : Theme.text4 }

    private var glyph: String { leaking ? "exclamationmark.triangle.fill" : "terminal" }

    private var glyphColor: Color { leaking ? Theme.amber : Theme.text3 }

    private var label: String {
        leaking ? "\(used) leaked" : formatHandles(used: used, max: max)
    }

    private var labelColor: Color { leaking ? Theme.amber : Theme.text3 }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            // Capacity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface3)
                    Capsule()
                        .fill(barColor)
                        .frame(width: Swift.max(geo.size.width * ratio, 2))
                }
            }
            .frame(height: 4)

            // Glyph + label channel
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: glyph)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(glyphColor)
                Text(label)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(labelColor)
                if leaking {
                    // The "climbing" tell is an up-arrow (not a second warning
                    // triangle): ⚠ N leaked  ↑ climbing.
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                        Text("climbing")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.amber)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Handle pool \(used) of \(max)")
    }
}
