// Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
// See LICENSE and NOTICE in the repository root.
import AppKit
import CoreServices

/// The `claude://` callback plumbing: registering Claude Profiles as the scheme's
/// handler (opt-in, reversible) and forwarding a received URL to one specific
/// Claude process.
///
/// Credential note: the callback URL carries a one-time auth code. This type holds
/// it only in memory for the instant of the hand-off and forwards it VERBATIM —
/// it never parses, logs, stores, or transmits it anywhere but the target Claude
/// process on this Mac (CLAUDE.md non-negotiable #1, as amended for v0.8).
public enum URLRouter {
    public static let scheme = "claude"
    /// UserDefaults key remembering who handled `claude://` before we took over,
    /// so turning routing off hands the scheme back. A bundle id, not a secret.
    static let previousHandlerKey = "claudeSchemePreviousHandler"

    // MARK: Handler registration

    /// The bundle id currently registered for `claude://`, if any.
    public static func currentHandler() -> String? {
        LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() as String?
    }

    /// True when this app is the registered `claude://` handler.
    public static func isEnabled(ownBundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
        guard let own = ownBundleID, let cur = currentHandler() else { return false }
        return cur.caseInsensitiveCompare(own) == .orderedSame
    }

    /// Take over `claude://`. Remembers the previous handler first. Returns false
    /// if LaunchServices refused.
    @discardableResult
    public static func enable(ownBundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
        guard let own = ownBundleID else { return false }
        if let cur = currentHandler(), cur.caseInsensitiveCompare(own) != .orderedSame {
            UserDefaults.standard.set(cur, forKey: previousHandlerKey)
        }
        return LSSetDefaultHandlerForURLScheme(scheme as CFString, own as CFString) == noErr
    }

    /// Hand `claude://` back to whoever had it (falls back to Claude's own
    /// bundle id, `com.anthropic.claudefordesktop`, when nothing was remembered).
    @discardableResult
    public static func disable(ownBundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
        let prev = UserDefaults.standard.string(forKey: previousHandlerKey)
            ?? "com.anthropic.claudefordesktop"
        let ok = LSSetDefaultHandlerForURLScheme(scheme as CFString, prev as CFString) == noErr
        if ok { UserDefaults.standard.removeObject(forKey: previousHandlerKey) }
        return ok
    }

    // MARK: Forwarding

    /// Deliver `url` to the Claude process `pid` as a `GetURL` Apple event — the
    /// same event macOS itself sends a URL handler, addressed to ONE process
    /// instead of whichever instance LaunchServices would pick. Fire-and-forget.
    /// Returns whether the event was sent (not whether Claude acted on it).
    /// Needs the Automation permission for Claude (one-time prompt).
    public static func forward(_ url: URL, toPID pid: Int32) -> Bool {
        let target = NSAppleEventDescriptor(processIdentifier: pid_t(pid))
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass),
            eventID: AEEventID(kAEGetURL),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: url.absoluteString),
                       forKeyword: AEKeyword(keyDirectObject))
        guard let desc = event.aeDesc else { return false }
        return AESendMessage(desc, nil, AESendMode(kAENoReply), kAEDefaultTimeout) == noErr
    }
}
