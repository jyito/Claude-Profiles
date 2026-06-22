import SwiftUI
import ProfilesCore

/// The Settings modal — the two opt-in automation knobs (three pickers), wired to
/// `getconfig`/`setconfig`. Pure view: takes the loaded `ProfileConfig` and an
/// `onChange(key, value)` sink; the scene performs `store.setConfig`.
///
/// Each picker maps an option to the engine's integer value; the picker's selection
/// reflects the current config (the nearest option, so an out-of-band value still
/// shows). Two rules carry amber ⚠ footgun notes (the spec's caution).
///
/// **Snapshot caveat:** native `Form`/`Picker` paint empty under `ImageRenderer`,
/// so in `snapshotMode` the rows render as a hand-built static stand-in (the chosen
/// option shown as a pill). The live app keeps the real `Form`/`Picker`.
public struct SettingsSheet: View {
    let config: ProfileConfig
    let onChange: (String, Int) -> Void
    let onClose: () -> Void

    @Environment(\.snapshotMode) private var snapshotMode

    public init(config: ProfileConfig,
                onChange: @escaping (String, Int) -> Void,
                onClose: @escaping () -> Void) {
        self.config = config
        self.onChange = onChange
        self.onClose = onClose
    }

    // MARK: Option model

    /// One picker option: a label + the engine integer it persists.
    struct Option: Hashable { let label: String; let value: Int }

    /// One automation rule: its key, title, options, and an optional amber footgun note.
    struct Rule {
        let key: ProfileConfig.Key
        let title: String
        let options: [Option]
        let warning: String?
    }

    private static let cleanRule = Rule(
        key: .autoCleanThresholdMB,
        title: "Auto-clean stopped profiles",
        options: [
            Option(label: "Off", value: 0),
            Option(label: "Over 500 MB", value: 500),
            Option(label: "Over 1 GB", value: 1024),
            Option(label: "Over 2 GB", value: 2048),
            Option(label: "Over 5 GB", value: 5120),
        ],
        warning: nil)

    private static let closeRule = Rule(
        key: .autoCloseIdleMin,
        title: "Auto-close idle terminals",
        options: [
            Option(label: "Off", value: 0),
            Option(label: "After 30 min", value: 30),
            Option(label: "After 1 hour", value: 60),
            Option(label: "After 2 hours", value: 120),
            Option(label: "After 4 hours", value: 240),
        ],
        warning: "Long silent tasks can look idle — a quiet build or a paused prompt may be closed.")

    private static let restartRule = Rule(
        key: .autoRestartLeakAt,
        title: "Auto-restart on handle leak",
        options: [
            Option(label: "Off", value: 0),
            Option(label: "At 150 handles", value: 150),
            Option(label: "At 250 handles", value: 250),
            Option(label: "At 350 handles", value: 350),
        ],
        warning: "Restarting closes that profile’s windows and terminals. The default instance is never auto-restarted.")

    private var rules: [Rule] { [Self.cleanRule, Self.closeRule, Self.restartRule] }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("Settings")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)

            Text("Both rules are off by default. They only ever delete regenerable caches or signal a profile — never your data or sign-ins.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            rulesSection

            Divider().overlay(Theme.hairline)

            HStack {
                Spacer(minLength: 0)
                Button { onClose() } label: { Text("Done") }
                    .buttonStyle(PillButtonStyle(.prominentCoral))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("settings-done")
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 460)
        .background(Theme.surface1)
    }

    // MARK: Rules

    @ViewBuilder private var rulesSection: some View {
        if snapshotMode {
            // Static stand-in: native Form/Picker render empty headless.
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                    standInRow(rule)
                }
            }
        } else {
            Form {
                ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                    liveRow(rule)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(height: 240)
        }
    }

    /// The selected option for a rule — exact value match, else "Off" (index 0) so an
    /// out-of-band persisted value never leaves the picker blank.
    private func selected(_ rule: Rule) -> Option {
        let v = config.value(for: rule.key)
        return rule.options.first { $0.value == v } ?? rule.options[0]
    }

    // MARK: Live (native Form + Picker)

    @ViewBuilder private func liveRow(_ rule: Rule) -> some View {
        Picker(selection: Binding(
            get: { selected(rule).value },
            set: { onChange(rule.key.rawValue, $0) }
        )) {
            ForEach(rule.options, id: \.value) { opt in
                Text(opt.label).tag(opt.value)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title)
                if let warning = rule.warning {
                    warningNote(warning)
                }
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("settings-\(rule.key.rawValue)")
    }

    // MARK: Snapshot stand-in (hand-built; native chrome paints empty headless)

    private func standInRow(_ rule: Rule) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(rule.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: Theme.Space.md)
                // The chosen option as a menu-pill (mirrors a closed Picker's look).
                HStack(spacing: 5) {
                    Text(selected(rule).label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                }
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .fill(Theme.surface3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .strokeBorder(Theme.hairlineLit, lineWidth: 1)
                )
            }
            if let warning = rule.warning {
                warningNote(warning)
            }
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

    private func warningNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.amber.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
