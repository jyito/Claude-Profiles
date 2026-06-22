import SwiftUI

/// The detail column's zero/first-load states. Both are pure + deterministic under
/// `ImageRenderer` (the shimmer freezes in `snapshotMode`).

/// Shown when there are no profiles at all — a muted window-stack glyph, one
/// sentence-case line, and the single coral New Profile CTA. Calm, not an error.
public struct EmptyStateView: View {
    let onNewProfile: () -> Void

    public init(onNewProfile: @escaping () -> Void = {}) {
        self.onNewProfile = onNewProfile
    }

    public var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.text4)
                .accessibilityHidden(true)
            Text("No profiles yet — create one to run a second Claude account.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                onNewProfile()
            } label: {
                Label("New Profile", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(.prominentCoral))
            .accessibilityIdentifier("empty-new-profile")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .accessibilityIdentifier("empty-state")
    }
}

/// First-load placeholder: a grid of card-shaped `surface2` rectangles with a
/// left→right shimmer (frozen mid-sweep in `snapshotMode`). Shown until the
/// store's first stats render, so the real grid fills in rather than popping.
public struct LoadingSkeletonView: View {
    /// How many placeholder cards to lay out (purely cosmetic).
    let count: Int

    @Environment(\.snapshotMode) private var snapshotMode
    @State private var shimmer = false

    public init(count: Int = 4) { self.count = count }

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: Theme.Space.lg)]

    public var body: some View {
        VStack(spacing: Theme.Space.lg) {
            // A short KPI-strip placeholder over the card grid placeholders.
            skeletonBar(height: 70)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.lg) {
                ForEach(0..<count, id: \.self) { _ in
                    skeletonBar(height: 200)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas)
        .onAppear {
            guard !snapshotMode else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
        .accessibilityIdentifier("loading-skeleton")
    }

    /// One rounded placeholder block with a diagonal highlight sweep.
    private func skeletonBar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.surface2)
            .frame(height: height)
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    // Frozen at a fixed offset in snapshotMode so the golden is stable.
                    let x = snapshotMode ? w * 0.35 : (shimmer ? w * 1.2 : -w * 0.4)
                    LinearGradient(
                        colors: [.clear, Theme.hairlineLit, .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: w * 0.5)
                    .offset(x: x)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}
