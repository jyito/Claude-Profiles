import SwiftUI
import ProfilesCore

/// Format the engine's idle-seconds into the inspector's terse label.
/// `-1` (unknown) → "—"; < 60s → "active"; else "Nm idle".
func formatIdle(_ seconds: Int) -> String {
    if seconds < 0 { return "—" }
    if seconds < 60 { return "active" }
    return "\(seconds / 60)m idle"
}

/// The running/default inspector's terminals drill-down: an eyebrow ("TERMINALS · N")
/// over one row per device — Device (SF-Mono, mint) · Command (SF-Mono, dimmed,
/// truncating) · Idle (right-aligned, monospacedDigit) · a per-row Close that
/// arms→confirms in place (unarmed "Close" → armed "Confirm" → `onClose(dev)`).
///
/// Built as a `VStack` of rows, not a native `Table`/`ScrollView` — those render
/// empty under `ImageRenderer`, so the golden harness needs an explicit layout.
public struct TerminalsTable: View {
    let terminals: [TerminalInfo]
    let onClose: (String) -> Void
    /// Snapshot-only: pre-arm one row's Close so the armed state is captured.
    let snapshotArmedDev: String?

    public init(terminals: [TerminalInfo],
                snapshotArmedDev: String? = nil,
                onClose: @escaping (String) -> Void) {
        self.terminals = terminals
        self.snapshotArmedDev = snapshotArmedDev
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("TERMINALS · \(terminals.count)")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.text3)

            if terminals.isEmpty {
                Text("No terminals open.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
                    .padding(.vertical, Theme.Space.xs)
            } else {
                VStack(spacing: 0) {
                    ForEach(terminals) { term in
                        TerminalRow(term: term,
                                    forceArmed: snapshotArmedDev == term.dev,
                                    onClose: onClose)
                        if term.id != terminals.last?.id {
                            Divider().overlay(Theme.hairline)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(Theme.surface1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
            }
        }
    }
}

/// One terminals row with an in-place arming Close control.
private struct TerminalRow: View {
    let term: TerminalInfo
    let forceArmed: Bool
    let onClose: (String) -> Void

    @Environment(\.snapshotMode) private var snapshotMode
    @State private var armed = false

    /// Short device name (drops `/dev/`) for the SF-Mono cell.
    private var shortDev: String {
        term.dev.hasPrefix("/dev/") ? String(term.dev.dropFirst("/dev/".count)) : term.dev
    }

    private var isArmed: Bool { forceArmed || armed }

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Text(shortDev)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.mint)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)

            Text(term.cmd)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatIdle(term.idle))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Theme.text2)
                .frame(width: 56, alignment: .trailing)

            closeButton
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 7)
    }

    private var closeButton: some View {
        Button {
            if isArmed {
                onClose(term.dev)
                armed = false
            } else {
                armed = true
                guard !snapshotMode else { return }
                // Auto-disarm after 3s if not confirmed.
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    armed = false
                }
            }
        } label: {
            Text(isArmed ? "Confirm" : "Close")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isArmed ? Color.black.opacity(0.85) : Theme.text2)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .fill(isArmed ? Theme.coral : Theme.surface3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .strokeBorder(isArmed ? Color.clear : Theme.hairlineLit, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("terminal-close-\(term.dev)")
    }
}
