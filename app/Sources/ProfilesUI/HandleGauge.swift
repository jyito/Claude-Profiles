import SwiftUI
import ProfilesCore

/// The leaked-handle (ptmx) capacity gauge. Three always-on channels — color +
/// glyph + number — so it survives grayscale / colorblindness. Calm gray under
/// warning; amber + triangle + "N leaked" (+ "▲ climbing" when rising) at
/// warning; coral at critical.
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

    private var barColor: Color {
        switch state {
        case .calm: return Theme.text4
        case .warning: return Theme.amber
        case .critical: return Theme.coral
        }
    }

    private var glyph: String {
        switch state {
        case .calm: return "terminal"
        case .warning, .critical: return "exclamationmark.triangle.fill"
        }
    }

    private var glyphColor: Color {
        switch state {
        case .calm: return Theme.text3
        case .warning: return Theme.amber
        case .critical: return Theme.coral
        }
    }

    private var label: String {
        switch state {
        case .calm:
            return formatHandles(used: used, max: max)
        case .warning(let climbing):
            return climbing ? "\(used) leaked  ▲ climbing" : "\(used) leaked"
        case .critical:
            return "\(used) leaked"
        }
    }

    private var labelColor: Color {
        switch state {
        case .calm: return Theme.text3
        case .warning: return Theme.amber
        case .critical: return Theme.coral
        }
    }

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
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Handle pool \(used) of \(max)")
    }
}
