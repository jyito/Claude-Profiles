import SwiftUI

/// An explicitly-drawn button style (capsule fill + hairline + tinted label) so
/// the chrome renders deterministically under `ImageRenderer` — AppKit's native
/// `.bordered`/`.borderedProminent` chrome and `Menu` indicators do NOT render in
/// the headless renderer (they paint as empty boxes). This style is token-exact
/// and snapshot-stable, and still shows hover/press states in the live app.
public struct PillButtonStyle: ButtonStyle {
    public enum Kind { case mint, neutral, prominentCoral }
    let kind: Kind

    public init(_ kind: Kind) { self.kind = kind }

    private var tint: Color {
        switch kind {
        case .mint: return Theme.mint
        case .neutral: return Theme.text2
        case .prominentCoral: return Theme.coral
        }
    }

    private func fill(_ pressed: Bool) -> Color {
        switch kind {
        case .prominentCoral:
            return Theme.coral.opacity(pressed ? 0.85 : 1.0)
        case .mint:
            return Theme.mint.opacity(pressed ? 0.22 : 0.14)
        case .neutral:
            return Theme.surface3.opacity(pressed ? 0.7 : 1.0)
        }
    }

    private var stroke: Color {
        switch kind {
        case .prominentCoral: return .clear
        case .mint: return Theme.mint.opacity(0.45)
        case .neutral: return Theme.hairlineLit
        }
    }

    private var labelColor: Color {
        switch kind {
        case .prominentCoral: return Color.black.opacity(0.85)
        case .mint: return Theme.mint
        case .neutral: return Theme.text2
        }
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(labelColor)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(fill(configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
    }
}
