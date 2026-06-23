// Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
// See LICENSE and NOTICE in the repository root.
//
// axdrive.swift — a tiny AXUIElement driver for the Layer-3 e2e smoke harness.
// Compiles with `swiftc` (no Xcode); drives the running "Claude Profiles" app by
// the accessibilityIdentifiers the SwiftUI views already set (e.g. "toolbar-new-
// profile", "empty-state", "card-<slug>-showwindow"). It finds elements by a DFS
// over the AX tree, presses them, and reads AXValue/AXDescription so flows.sh can
// assert against what the app actually rendered.
//
// REQUIRES an Accessibility (AXIsProcessTrusted) grant for the process running it
// — Terminal/the test runner — which is why this is a maintainer gate and not
// hosted CI (SIP blocks the TCC grant on GitHub runners). See docs/E2E.md.
//
// Usage:
//   axdrive wait    <appName> <identifier> [timeoutSec]   # 0 when it appears, 7 on timeout
//   axdrive press   <appName> <identifier>                # 0 when pressed, 4 when not found
//   axdrive value   <appName> <identifier>                # prints AXValue/AXDescription/AXTitle
//   axdrive dump    <appName>                             # prints every identifier in the tree
//
// Exit codes: 0 ok · 2 usage · 3 app-not-running · 4 element-not-found · 5 not-trusted
//             6 press-failed · 7 wait-timeout

import AppKit
import ApplicationServices

// MARK: - AX attribute helpers

private func copyAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(el, attr as CFString, &value)
    return err == .success ? value : nil
}

private func stringAttr(_ el: AXUIElement, _ attr: String) -> String? {
    copyAttr(el, attr) as? String
}

private func children(_ el: AXUIElement) -> [AXUIElement] {
    (copyAttr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

/// AXIdentifier is the bridge for `.accessibilityIdentifier(...)` in SwiftUI.
private func identifier(_ el: AXUIElement) -> String? {
    stringAttr(el, "AXIdentifier")
}

// MARK: - tree walk

private func appElement(named appName: String) -> AXUIElement? {
    let apps = NSWorkspace.shared.runningApplications.filter {
        ($0.localizedName == appName) || ($0.bundleIdentifier?.contains("claude-profiles") ?? false)
    }
    guard let pid = apps.first?.processIdentifier else { return nil }
    return AXUIElementCreateApplication(pid)
}

/// Depth-first search for the first element whose AXIdentifier == id (bounded depth
/// so a runaway tree can't hang the driver).
private func find(_ root: AXUIElement, id: String, depth: Int = 0) -> AXUIElement? {
    if depth > 40 { return nil }
    if identifier(root) == id { return root }
    for child in children(root) {
        if let hit = find(child, id: id, depth: depth + 1) { return hit }
    }
    return nil
}

/// Collect every non-empty AXIdentifier in the tree (for `dump`, to debug flows).
private func collectIdentifiers(_ root: AXUIElement, into acc: inout [String], depth: Int = 0) {
    if depth > 40 { return }
    if let id = identifier(root), !id.isEmpty { acc.append(id) }
    for child in children(root) { collectIdentifiers(child, into: &acc, depth: depth + 1) }
}

// MARK: - driver

private func fail(_ msg: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data(("axdrive: " + msg + "\n").utf8))
    exit(code)
}

private func requireApp(_ name: String) -> AXUIElement {
    if let app = appElement(named: name) { return app }
    fail("app not running: \(name)", 3)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    fail("usage: axdrive <wait|press|value|dump> <appName> [identifier] [timeout]", 2)
}

// The driver itself must be a trusted (Accessibility-granted) process.
if !AXIsProcessTrusted() {
    fail("not Accessibility-trusted — grant the test runner in System Settings > Privacy & Security > Accessibility", 5)
}

let cmd = args[1]
let appName = args[2]

switch cmd {
case "dump":
    let app = requireApp(appName)
    var ids: [String] = []
    collectIdentifiers(app, into: &ids)
    for id in ids { print(id) }
    exit(0)

case "wait":
    guard args.count >= 4 else { fail("wait needs <identifier> [timeout]", 2) }
    let id = args[3]
    let timeout = (args.count >= 5 ? Double(args[4]) : nil) ?? 10.0
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let app = requireApp(appName)
        if find(app, id: id) != nil { exit(0) }
        Thread.sleep(forTimeInterval: 0.25)
    }
    fail("timed out waiting for \(id) after \(timeout)s", 7)

case "press":
    guard args.count >= 4 else { fail("press needs <identifier>", 2) }
    let id = args[3]
    let app = requireApp(appName)
    guard let el = find(app, id: id) else { fail("element not found: \(id)", 4) }
    let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
    if err != .success { fail("press failed for \(id) (AXError \(err.rawValue))", 6) }
    exit(0)

case "value":
    guard args.count >= 4 else { fail("value needs <identifier>", 2) }
    let id = args[3]
    let app = requireApp(appName)
    guard let el = find(app, id: id) else { fail("element not found: \(id)", 4) }
    let out = stringAttr(el, kAXValueAttribute as String)
        ?? stringAttr(el, kAXDescriptionAttribute as String)
        ?? stringAttr(el, kAXTitleAttribute as String)
        ?? ""
    print(out)
    exit(0)

default:
    fail("unknown command: \(cmd)", 2)
}
