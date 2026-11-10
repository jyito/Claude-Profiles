// Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
// See LICENSE and NOTICE in the repository root.
import AppKit
import ApplicationServices
import ProfilesCore

/// One thing to tile: a Claude Desktop instance's window (by PID) or a Claude Code
/// terminal session (a Terminal window attached to `screen -x claude-<slug>`).
public enum ArrangeTarget: Sendable, Equatable {
    case desktop(slug: String, pid: Int32)
    /// `tty` is the Terminal window already attached to the session (nil = none:
    /// a new Terminal window is opened and attached, but only for a live session).
    case terminal(slug: String, tty: String?)
}

public struct ArrangeResult: Sendable, Equatable {
    public var placed = 0
    /// Human-readable reasons for anything that could not be placed.
    public var skipped: [String] = []
}

/// Side-by-side window tiling for Claude Desktop instances (Accessibility API) and
/// Claude Code terminals (Terminal's own AppleScript). Geometry comes from the pure,
/// tested `stackFrames`; this file only translates it to each API's coordinates and
/// applies it. Live behavior is maintainer-verified (needs real windows + the
/// Accessibility permission).
public enum Arrange {
    // MARK: Accessibility permission (the project's second permission, desktop only)

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Trigger the system Accessibility prompt (once) and return the current state.
    @discardableResult
    public static func requestTrust() -> Bool {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: Entry point

    /// Tile `targets` across `bounds` (Cocoa `visibleFrame`, y-up). Order = tile
    /// order, row-major from the top-left.
    @MainActor
    public static func stack(_ targets: [ArrangeTarget], in bounds: CGRect) -> ArrangeResult {
        var result = ArrangeResult()
        let frames = stackFrames(in: bounds, count: targets.count)
        guard frames.count == targets.count else {
            result.skipped.append("Nothing to arrange.")
            return result
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? bounds.maxY
        for (target, frame) in zip(targets, frames) {
            // Cocoa (origin bottom-left, y-up) → AX/Terminal (origin top-left, y-down).
            let rect = CGRect(x: frame.minX, y: primaryHeight - frame.maxY,
                              width: frame.width, height: frame.height)
            switch target {
            case .desktop(let slug, let pid):
                if placeDesktop(pid: pid, rect: rect) { result.placed += 1 }
                else { result.skipped.append("\(slug): no window to move") }
            case .terminal(let slug, let tty):
                if placeTerminal(slug: slug, tty: tty, rect: rect) { result.placed += 1 }
                else { result.skipped.append("\(slug): terminal not placed") }
            }
        }
        return result
    }

    // MARK: Desktop (AX)

    private static func placeDesktop(pid: Int32, rect: CGRect) -> Bool {
        guard isTrusted else { return false }
        let app = AXUIElementCreateApplication(pid_t(pid))
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        // First window that is not minimized; fall back to the first one.
        let window = windows.first(where: { !boolAttr($0, kAXMinimizedAttribute) }) ?? windows.first
        guard let window else { return false }
        if boolAttr(window, kAXMinimizedAttribute) {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        var size = rect.size, origin = rect.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let posValue = AXValueCreate(.cgPoint, &origin) else { return false }
        // size → position → size again: moving can clamp the size against a screen
        // edge, and some windows only honor the final size once they are in place.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return moved == .success
    }

    private static func boolAttr(_ el: AXUIElement, _ name: String) -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return false }
        return (v as? Bool) ?? false
    }

    // MARK: Terminal (AppleScript)

    /// Validated before interpolation: only values the engine itself could have
    /// produced ever reach the script text.
    static func validTTY(_ s: String) -> Bool {
        s.range(of: #"^/dev/ttys[0-9]+$"#, options: .regularExpression) != nil
    }
    static func validSlug(_ s: String) -> Bool {
        !s.isEmpty && s.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil
    }

    static func terminalScript(slug: String, tty: String?, rect: CGRect) -> String? {
        let l = Int(rect.minX.rounded()), t = Int(rect.minY.rounded())
        let r = Int(rect.maxX.rounded()), b = Int(rect.maxY.rounded())
        if let tty {
            guard validTTY(tty) else { return nil }
            return """
            tell application "Terminal"
                repeat with w in windows
                    try
                        if (tty of selected tab of w) is "\(tty)" then
                            set bounds of w to {\(l), \(t), \(r), \(b)}
                            return "ok"
                        end if
                    end try
                end repeat
                return "missing"
            end tell
            """
        }
        guard validSlug(slug) else { return nil }
        return """
        tell application "Terminal"
            do script "screen -x claude-\(slug)"
            set bounds of front window to {\(l), \(t), \(r), \(b)}
            return "ok"
        end tell
        """
    }

    private static func placeTerminal(slug: String, tty: String?, rect: CGRect) -> Bool {
        guard let src = terminalScript(slug: slug, tty: tty, rect: rect),
              let script = NSAppleScript(source: src) else { return false }
        var err: NSDictionary?
        let out = script.executeAndReturnError(&err)
        return err == nil && out.stringValue == "ok"
    }
}
