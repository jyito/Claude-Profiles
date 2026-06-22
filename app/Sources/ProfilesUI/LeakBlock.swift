import SwiftUI
import ProfilesCore

/// The leaked-handle restart tile. Shown when `ptmx > 0`: macOS can't reclaim the
/// `/dev/ptmx` masters Claude Desktop leaks (bundled node-pty bug) — only a restart
/// frees them. Framing follows severity (amber at `.warning`, coral at `.critical`,
/// otherwise a calm amber tint). The Restart is **2-step** (arm → confirm) and the
/// confirm copy spells out the quit/reopen so it never surprises.
public struct LeakBlock: View {
    let stat: ProfileStat
    let state: AlertState
    let onRestart: () -> Void

    @Environment(\.snapshotMode) private var snapshotMode
    @State private var armed = false
    /// Snapshot-only: render the armed ("Confirm Restart") state.
    let snapshotArmed: Bool

    public init(stat: ProfileStat,
                state: AlertState,
                snapshotArmed: Bool = false,
                onRestart: @escaping () -> Void) {
        self.stat = stat
        self.state = state
        self.snapshotArmed = snapshotArmed
        self.onRestart = onRestart
    }

    private var isArmed: Bool { snapshotArmed || armed }

    /// Accent follows severity; default to amber when merely leaking but not yet warning.
    private var accent: Color {
        switch state {
        case .critical: return Theme.coral
        case .warning, .calm: return Theme.amber
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text("Leaked handles")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(accent)
            }

            Text("\(stat.ptmx) leaked terminal handles macOS can't reclaim (a Claude Desktop bug). Restart frees them.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            if isArmed {
                Text("This quits and reopens Claude — windows and terminals close; login and chats are kept.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            restartButton
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(accent.opacity(0.55), lineWidth: 1)
        )
    }

    private var restartButton: some View {
        Button {
            if isArmed {
                onRestart()
                armed = false
            } else {
                armed = true
                guard !snapshotMode else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    armed = false
                }
            }
        } label: {
            Text(isArmed ? "Confirm Restart" : "Restart to Free Handles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isArmed ? Color.black.opacity(0.85) : accent)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(isArmed ? accent : accent.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(isArmed ? Color.clear : accent.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inspector-restart")
    }
}
