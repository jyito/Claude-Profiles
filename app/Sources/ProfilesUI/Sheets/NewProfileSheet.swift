import SwiftUI
import ProfilesCore

/// The New Profile modal. A single name field with a **live identity-disc preview**:
/// as the user types, the badge color + initial update to exactly what the engine
/// will assign (`BadgePreview.slugify` → `badgeColorIndex` → `Theme.badgePalette`),
/// so the chosen color is no surprise. Pure view — `onCreate(name)` / `onCancel()`
/// closures; the scene owns the engine `create` call.
public struct NewProfileSheet: View {
    let onCreate: (String) -> Void
    let onCancel: () -> Void
    /// Snapshot-only: a fixed typed value so the golden renders a populated preview
    /// (the native `TextField` paints empty under `ImageRenderer`).
    let snapshotText: String?

    @Environment(\.snapshotMode) private var snapshotMode
    @State private var text = ""

    public init(snapshotText: String? = nil,
                onCreate: @escaping (String) -> Void,
                onCancel: @escaping () -> Void) {
        self.snapshotText = snapshotText
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    /// The effective text: the fixed snapshot value, else the live field.
    private var typed: String { snapshotText ?? text }
    private var trimmed: String { typed.trimmingCharacters(in: .whitespaces) }
    private var slug: String { BadgePreview.slugify(trimmed) }
    /// Disabled until the name yields a non-empty slug (the engine would `err` otherwise).
    private var canCreate: Bool { !slug.isEmpty }

    private var previewIndex: Int { BadgePreview.badgeColorIndex(forSlug: slug) }
    private var previewColor: Color { Theme.badgeColor(for: previewIndex) }
    private var previewInitial: String { BadgePreview.initial(forName: trimmed) }

    /// Human-readable color name for the caption, in `Theme.badgePalette` order.
    private static let colorNames = ["blue", "mint", "amber", "purple", "pink", "teal"]
    private var previewColorName: String { Self.colorNames[previewIndex] }
    /// "an" before a vowel-initial color name (amber), "a" otherwise.
    private var previewArticle: String { "aeiou".contains(previewColorName.first ?? "x") ? "an" : "a" }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("New profile")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)

            Text("Each profile is a separate Claude Desktop with its own login. Pick a name — it gets a colored badge so you can tell its Dock icon apart.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            identityRow

            if canCreate {
                Text("‘\(trimmed)’ gets \(previewArticle) \(previewColorName) badge with \(previewInitial).")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
            } else {
                Text("Use letters or numbers — they form the profile’s id.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
            }

            Divider().overlay(Theme.hairline)

            buttonRow
        }
        .padding(Theme.Space.xl)
        .frame(width: 420)
        .background(Theme.surface1)
    }

    // MARK: Identity row — live preview disc beside the name field

    private var identityRow: some View {
        HStack(spacing: Theme.Space.md) {
            previewDisc
            nameField
        }
    }

    /// The live badge preview. Drawn directly (not via `BadgeDisc`, which keys off a
    /// stored hex) so it reflects the *previewed* palette index as the user types.
    private var previewDisc: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.disc, style: .continuous)
            .fill(canCreate ? previewColor : Theme.surface3)
            .frame(width: 40, height: 40)
            .overlay {
                Text(canCreate ? previewInitial : "?")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(canCreate ? Color.black.opacity(0.8) : Theme.text3)
            }
            .accessibilityIdentifier("newprofile-preview")
    }

    /// Editable name field in the live app; a static stand-in under `ImageRenderer`
    /// (the native `TextField` paints as an empty yellow box headless).
    @ViewBuilder private var nameField: some View {
        Group {
            if snapshotMode {
                Text(typed.isEmpty ? "Profile name" : typed)
                    .font(.system(size: 14))
                    .foregroundStyle(typed.isEmpty ? Theme.text3 : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Profile name", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                    .onSubmit { if canCreate { onCreate(trimmed) } }
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Theme.surface2)
        )
        .overlay(
            // Coral focus ring (the project's single accent ring).
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(canCreate ? Theme.coral.opacity(0.55) : Theme.hairlineLit, lineWidth: 1)
        )
        .accessibilityIdentifier("newprofile-field")
    }

    // MARK: Buttons

    private var buttonRow: some View {
        HStack(spacing: Theme.Space.sm) {
            Spacer(minLength: 0)
            Button(role: .cancel) { onCancel() } label: { Text("Cancel") }
                .buttonStyle(PillButtonStyle(.neutral))
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("newprofile-cancel")

            Button { if canCreate { onCreate(trimmed) } } label: { Text("Create Profile") }
                .buttonStyle(PillButtonStyle(.prominentCoral))
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.5)
                .accessibilityIdentifier("newprofile-create")
        }
    }
}
