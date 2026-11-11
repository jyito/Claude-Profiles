// Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
// See LICENSE and NOTICE in the repository root.
import SwiftUI
import ProfilesCore

/// The strip above the grid while a sign-in has closed other instances: names the
/// target, says how many were closed, and offers Restore / Dismiss. Pure view; the
/// scene wires the buttons to `StatsStore.restoreSignIn` / `dismissSignIn`.
public struct SignInBanner: View {
    let targetName: String?
    let closedCount: Int
    let onRestore: () -> Void
    let onDismiss: () -> Void

    public init(targetName: String?, closedCount: Int,
                onRestore: @escaping () -> Void = {},
                onDismiss: @escaping () -> Void = {}) {
        self.targetName = targetName
        self.closedCount = closedCount
        self.onRestore = onRestore
        self.onDismiss = onDismiss
    }

    private var headline: String {
        if let targetName { return "Signing in to \(targetName)" }
        return "A sign-in is in progress"
    }

    private var detail: String {
        let n = closedCount == 1 ? "1 other Claude is" : "\(closedCount) other Claudes are"
        return "\(n) closed so the login lands here. Restore reopens them, still signed in."
    }

    public var body: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: Theme.Space.md)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(PillButtonStyle(.neutral))
                .accessibilityIdentifier("signin-banner-dismiss")
            Button("Restore", action: onRestore)
                .buttonStyle(PillButtonStyle(.prominentCoral))
                .accessibilityIdentifier("signin-banner-restore")
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Theme.amber.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(Theme.amber.opacity(0.35), lineWidth: 1)
        )
        .accessibilityIdentifier("signin-banner")
    }
}
