import SwiftUI

/// The running/stopped indicator. Running = mint with a canvas-colored ring and a
/// slow breathing pulse (disabled in snapshotMode). Stopped = hollow gray ring.
public struct StatusDot: View {
    let running: Bool
    let size: CGFloat

    @Environment(\.snapshotMode) private var snapshotMode
    @State private var pulsing = false

    public init(running: Bool, size: CGFloat = 8) {
        self.running = running
        self.size = size
    }

    public var body: some View {
        Group {
            if running {
                Circle()
                    .fill(Theme.mint)
                    .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: 1.5))
                    .opacity(snapshotMode ? 1.0 : (pulsing ? 0.55 : 1.0))
                    .onAppear {
                        guard !snapshotMode else { return }
                        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                            pulsing = true
                        }
                    }
            } else {
                Circle()
                    .strokeBorder(Theme.text4, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
