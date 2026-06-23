import SwiftUI
import ProfilesCore

/// The stopped-profile clean tiers. Eyebrow "STORAGE" + "Using X on disk", then a
/// 2×2 grid of bordered tiles — Caches / GPU / Logs / Everything. Each tap fires
/// `onClean(tier)` with **no confirmation**: every tier deletes only regenerable
/// Electron caches (the engine refuses while running). Shown only for stopped,
/// non-default instances (gated by the caller).
public struct CleanTiers: View {
    let disk: Int
    let onClean: (String) -> Void

    public init(disk: Int, onClean: @escaping (String) -> Void) {
        self.disk = disk
        self.onClean = onClean
    }

    private struct Tier { let key: String; let title: String; let desc: String; let hint: String }

    private let tiers: [Tier] = [
        Tier(key: "caches", title: "Caches", desc: "Code & render cache", hint: "regenerates on launch"),
        Tier(key: "gpu",    title: "GPU",    desc: "Shader cache",        hint: "regenerates on launch"),
        Tier(key: "logs",   title: "Logs",   desc: "Diagnostic logs",     hint: "safe to clear"),
        Tier(key: "all",    title: "Everything", desc: "All regenerable", hint: "caches · GPU · logs"),
    ]

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Space.sm),
        GridItem(.flexible(), spacing: Theme.Space.sm),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("STORAGE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.text3)
            Text("Using \(formatDiskMB(disk)) on disk")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.text2)

            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.sm) {
                ForEach(tiers, id: \.key) { tier in
                    tile(tier)
                }
            }
        }
    }

    private func tile(_ tier: Tier) -> some View {
        Button {
            onClean(tier.key)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(tier.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(tier.desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                Text(tier.hint)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .accessibilityIdentifier("inspector-clean-\(tier.key)")
    }
}
