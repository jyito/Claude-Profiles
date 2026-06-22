import AppKit

/// In-process window activation by PID — the SwiftUI twin of the AppleScriptObjC
/// `focusInstance` (and `engine focus`'s headless path). Used by the card's Show
/// Window button and the menu-bar switcher.
///
/// Targets the PID, NEVER the bundle id: every profile wrapper launches the same
/// Claude.app, so all instances share one bundle id — only the PID disambiguates.
///
/// Live behavior (window raising, the one-time Automation prompt, cross-Spaces) is
/// maintainer-verified; the Phase-0 spike (`spike/Sources/SpikeCore/Focus.swift`)
/// already proved this exact mechanism (spike criteria #3/#4 PASS).
public enum Focus {
    /// Raise an instance's windows by PID. `NSRunningApplication` activation runs
    /// first; if macOS 14+ cooperative activation declines it (common across Spaces,
    /// other displays, or fullscreen), fall back after 0.3s to System Events
    /// `frontmost` — which reliably travels across Spaces but asks the CALLER for
    /// Automation once (the project's only permission prompt).
    @MainActor
    public static func show(pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { return }
        // yieldActivation cedes our app's activation token so the target can take
        // foreground — macOS 14+ only (the package's deployment target, but the
        // guard documents the requirement and keeps the call site honest).
        if #available(macOS 14, *) { NSApp?.yieldActivation(to: app) }
        app.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !app.isActive { systemEventsFrontmost(pid: pid) }
        }
    }

    /// System Events frontmost via `osascript` (a macOS built-in). Fire-and-forget:
    /// the only side effect we need is the foreground switch + the Automation grant.
    private static func systemEventsFrontmost(pid: Int32) {
        let src = "tell application \"System Events\" to set frontmost of (first application process whose unix id is \(pid)) to true"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", src]
        try? p.run()
    }
}
