import SwiftUI
import ProfilesCore

/// The stopped-profile badge color picker: a row of 6 disc swatches in the engine
/// palette order (blue / mint / amber / purple / pink / teal). The active swatch is
/// ringed in primary text; tapping fires `onPick(index)` → `engine setbadge`.
/// Absent on the default instance (the caller gates it out).
public struct BadgePicker: View {
    let currentHex: String
    let slug: String
    let onPick: (Int) -> Void

    public init(currentHex: String, slug: String = "", onPick: @escaping (Int) -> Void) {
        self.currentHex = currentHex
        self.slug = slug
        self.onPick = onPick
    }

    /// The engine palette as `#RRGGBB`, in `badge_palette` order — used to detect
    /// which swatch is active from the stat's color field.
    static let paletteHex = ["#3B7DD8", "#5DCAA5", "#E0A333", "#7C5CC4", "#D25F8C", "#4CA9B2"]

    private var activeIndex: Int? {
        let norm = currentHex.uppercased()
        return Self.paletteHex.firstIndex { $0.uppercased() == norm }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("BADGE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.text3)

            HStack(spacing: Theme.Space.md) {
                ForEach(0..<Theme.badgePalette.count, id: \.self) { i in
                    swatch(i)
                }
            }
        }
    }

    private func swatch(_ index: Int) -> some View {
        let isActive = activeIndex == index
        return Button {
            onPick(index)
        } label: {
            Circle()
                .fill(Theme.badgeColor(for: index))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .strokeBorder(isActive ? Theme.text : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inspector-badge-\(index)")
    }
}
