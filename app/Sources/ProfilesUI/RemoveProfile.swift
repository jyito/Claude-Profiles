import SwiftUI
import ProfilesCore

/// The stopped-profile destructive remove. A quiet muted text button at the very
/// bottom that expands to a `TextField` where the user types the **account's own
/// name** (not "DELETE" — guards the work/work2 prefix hazard). The "Remove
/// Permanently" button stays disabled until the typed text exactly matches `name`,
/// then renders desaturated red (never coral). Absent on the default instance.
public struct RemoveProfile: View {
    let name: String
    let onRemove: () -> Void
    /// Snapshot-only: render expanded with the field pre-filled to `name`.
    let snapshotExpanded: Bool

    public init(name: String, snapshotExpanded: Bool = false, onRemove: @escaping () -> Void) {
        self.name = name
        self.snapshotExpanded = snapshotExpanded
        self.onRemove = onRemove
    }

    /// Desaturated red — deliberately NOT the brand coral, so destructive never
    /// borrows the accent's affordance.
    private static let dangerRed = Color(hex: 0xB05242)

    @State private var expanded = false
    @State private var typed = ""

    private var isExpanded: Bool { snapshotExpanded || expanded }
    private var effectiveTyped: String { snapshotExpanded ? name : typed }
    private var matches: Bool { effectiveTyped == name }

    public var body: some View {
        if isExpanded {
            expandedForm
        } else {
            Button {
                expanded = true
            } label: {
                Text("Remove Profile…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("inspector-remove-disclose")
        }
    }

    private var expandedForm: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Type the profile's name to remove it")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)

            TextField(name, text: $typed)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(Theme.surface1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Theme.hairlineLit, lineWidth: 1)
                )
                .accessibilityIdentifier("inspector-remove-field")

            HStack(spacing: Theme.Space.sm) {
                Button {
                    if matches { onRemove() }
                } label: {
                    Text("Remove Permanently")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(matches ? Color.white.opacity(0.95) : Theme.text4)
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                                .fill(matches ? Self.dangerRed : Theme.surface2)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!matches)
                .accessibilityIdentifier("inspector-remove-confirm")

                Button {
                    expanded = false
                    typed = ""
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inspector-remove-cancel")
            }

            Text("This permanently deletes the profile and its data — it can't be undone.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Space.xs)
    }
}
