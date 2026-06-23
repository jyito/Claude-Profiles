import SwiftUI
import ProfilesCore

/// A bulk maintenance action this sheet can request. The scene maps each to the
/// matching engine verb (`quitall` / `cleanall` / `killswitch`).
public enum CleanupAction: Equatable, Sendable {
    case quitAll        // engine quitall — graceful TERM to every running profile (default untouched)
    case cleanAll       // engine cleanall — clear caches on every STOPPED profile
    case emergencyStop  // engine killswitch — SIGKILL every Claude tree, default included
}

/// The Cleanup modal — three bulk actions. Quit All and Clear Caches fire on tap;
/// **Emergency Stop is 2-step (arm → confirm)** and rendered in desaturated red
/// (never coral) since it force-quits everything including the default instance.
/// Pure view: `onAction(CleanupAction)`; the scene performs the engine call.
public struct CleanupSheet: View {
    let onAction: (CleanupAction) -> Void
    let onClose: () -> Void
    /// Snapshot-only: render the Emergency Stop row in its armed ("Confirm" / red) state.
    let snapshotEmergencyArmed: Bool

    @Environment(\.snapshotMode) private var snapshotMode
    @State private var emergencyArmed = false

    public init(snapshotEmergencyArmed: Bool = false,
                onAction: @escaping (CleanupAction) -> Void,
                onClose: @escaping () -> Void) {
        self.snapshotEmergencyArmed = snapshotEmergencyArmed
        self.onAction = onAction
        self.onClose = onClose
    }

    /// Desaturated red — deliberately NOT the brand coral (matches `RemoveProfile`).
    private static let dangerRed = Color(hex: 0xB05242)
    private var isArmed: Bool { snapshotEmergencyArmed || emergencyArmed }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("Cleanup")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)

            Text("Bulk maintenance across all profiles. None of these touch your data or sign-ins.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            quitAllRow
            cleanAllRow
            emergencyRow

            Divider().overlay(Theme.hairline)

            HStack {
                Spacer(minLength: 0)
                Button { onClose() } label: { Text("Done") }
                    .buttonStyle(PillButtonStyle(.neutral))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cleanup-done")
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 440)
        .background(Theme.surface1)
    }

    // MARK: Rows

    private var quitAllRow: some View {
        actionRow(
            title: "Quit All Profiles",
            sub: "Gracefully quits every running profile. The default Claude keeps running.",
            actionLabel: "Quit All",
            kind: .neutral,
            id: "cleanup-quitall"
        ) { onAction(.quitAll) }
    }

    private var cleanAllRow: some View {
        actionRow(
            title: "Clear Caches on Stopped",
            sub: "Frees disk by clearing regenerable caches on stopped profiles. Running profiles are skipped.",
            actionLabel: "Clear Caches",
            kind: .neutral,
            id: "cleanup-cleanall"
        ) { onAction(.cleanAll) }
    }

    /// A generic bordered action row (Quit All / Clear Caches). The Emergency row is
    /// separate because it's 2-step + danger-styled.
    private func actionRow(title: String, sub: String, actionLabel: String,
                           kind: PillButtonStyle.Kind, id: String,
                           perform: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.sm)
            Button { perform() } label: { Text(actionLabel) }
                .buttonStyle(PillButtonStyle(kind))
                .accessibilityIdentifier(id)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Theme.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    // MARK: Emergency Stop (desaturated-red, 2-step arm → confirm)

    private var emergencyRow: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Emergency Stop")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.dangerRed)
                Text(isArmed
                     ? "Force-quits ALL Claude instances including the default — unsaved work in any of them is lost."
                     : "Force-quits all profile instances and the default. A last resort when something is wedged.")
                    .font(.system(size: 11))
                    .foregroundStyle(isArmed ? Self.dangerRed.opacity(0.9) : Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.sm)
            emergencyButton
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Self.dangerRed.opacity(isArmed ? 0.14 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(Self.dangerRed.opacity(isArmed ? 0.7 : 0.4), lineWidth: 1)
        )
    }

    private var emergencyButton: some View {
        Button {
            if isArmed {
                onAction(.emergencyStop)
                emergencyArmed = false
            } else {
                emergencyArmed = true
                guard !snapshotMode else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    emergencyArmed = false
                }
            }
        } label: {
            Text(isArmed ? "Confirm Stop" : "Emergency Stop")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isArmed ? Color.white.opacity(0.95) : Self.dangerRed)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(isArmed ? Self.dangerRed : Self.dangerRed.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(isArmed ? Color.clear : Self.dangerRed.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .accessibilityIdentifier("cleanup-emergency")
    }
}
