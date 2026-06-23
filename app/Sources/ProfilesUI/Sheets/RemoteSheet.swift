import SwiftUI
import ProfilesCore

/// The Remote-access modal. Shows the copy-paste SSH commands to attach to a
/// profile's Claude Code `screen` session — a local-network block and, when a
/// Tailscale IP exists, an any-network block — each with a Copy button, plus a QR
/// of the local attach command and collapsible iPad / Tailscale setup steps.
/// Pure view: `onCopy(text)` / `onStop()` / `onClose()`; the scene performs the
/// `engine copy` / `remotestop`.
public struct RemoteSheet: View {
    let name: String
    let info: RemoteInfo
    let onCopy: (String) -> Void
    let onStop: () -> Void
    let onClose: () -> Void
    /// Snapshot-only: render the setup steps expanded so the golden covers them.
    let snapshotStepsExpanded: Bool

    @Environment(\.snapshotMode) private var snapshotMode
    @State private var stepsExpanded = false

    public init(name: String,
                info: RemoteInfo,
                snapshotStepsExpanded: Bool = false,
                onCopy: @escaping (String) -> Void,
                onStop: @escaping () -> Void = {},
                onClose: @escaping () -> Void) {
        self.name = name
        self.info = info
        self.snapshotStepsExpanded = snapshotStepsExpanded
        self.onCopy = onCopy
        self.onStop = onStop
        self.onClose = onClose
    }

    private var showSteps: Bool { snapshotStepsExpanded || stepsExpanded }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            header

            if let error = info.error {
                errorBlock(error)
            } else {
                connectBody
            }

            Divider().overlay(Theme.hairline)

            HStack {
                // The session is running by the time this modal opens (`remoteinfo`
                // started/reused it), so a missing error means there's a session to
                // stop. This is the only "turn Remote OFF" affordance.
                if info.error == nil {
                    Button { onStop() } label: { Text("Stop session") }
                        .buttonStyle(PillButtonStyle(.neutral))
                        .accessibilityIdentifier("remote-stop")
                }
                Spacer(minLength: 0)
                Button { onClose() } label: { Text("Done") }
                    .buttonStyle(PillButtonStyle(.neutral))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("remote-done")
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 480)
        .background(Theme.surface1)
    }

    // MARK: Header (title + live dot)

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Text("Remote access — \(name)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            if info.error == nil && info.alreadyRunning {
                HStack(spacing: 4) {
                    Circle().fill(Theme.mint).frame(width: 6, height: 6)
                    Text("live")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.mint)
                }
                .accessibilityIdentifier("remote-live")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Connect body

    private var connectBody: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("Attach to this profile’s Claude Code session from another machine. Paste a command, or scan the code.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    commandBlock(label: "On the same network",
                                 command: info.localCommand,
                                 id: "remote-copy-local")
                    if let ts = info.tailscaleCommand {
                        commandBlock(label: "From any network (Tailscale)",
                                     command: ts,
                                     id: "remote-copy-tailscale")
                    }
                }
                qrBlock
            }

            stepsDisclosure
        }
    }

    /// One labelled SF-Mono command block with a Copy button.
    private func commandBlock(label: String, command: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.text3)
            HStack(alignment: .center, spacing: Theme.Space.sm) {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { onCopy(command) } label: { Text("Copy") }
                    .buttonStyle(PillButtonStyle(.neutral))
                    .accessibilityIdentifier(id)
            }
            .padding(Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
        }
    }

    /// The QR of the local attach command. `CIQRCodeGenerator` renders deterministically
    /// headlessly, so the snapshot uses the real code (no stand-in needed).
    @ViewBuilder private var qrBlock: some View {
        if let nsImage = QRCode.image(for: info.localCommand, points: 132) {
            VStack(spacing: Theme.Space.xs) {
                Image(nsImage: nsImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 116, height: 116)
                    .padding(Theme.Space.sm)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                Text("Scan to attach")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text3)
            }
            .accessibilityIdentifier("remote-qr")
        }
    }

    // MARK: Setup steps (collapsible)

    private var stepsDisclosure: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Button {
                stepsExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showSteps ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Show iPad / Tailscale setup")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text2)
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .accessibilityIdentifier("remote-steps-toggle")

            if showSteps {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                            Text("\(i + 1).")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.text3)
                                .frame(width: 16, alignment: .trailing)
                            Text(step)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, Theme.Space.xs)
            }
        }
    }

    private static let steps: [String] = [
        "Enable SSH on this Mac: System Settings → General → Sharing → Remote Login.",
        "Install Tailscale on this Mac and the iPad, sign both into the same account.",
        "On the iPad, install an SSH client (e.g. Blink Shell or Termius).",
        "Paste the any-network command above (or scan the code) to attach to the session.",
    ]

    // MARK: Error path

    private func errorBlock(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Theme.amber.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(Theme.amber.opacity(0.5), lineWidth: 1)
        )
        .accessibilityIdentifier("remote-error")
    }
}
