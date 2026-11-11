// Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
// See LICENSE and NOTICE in the repository root.
import AppKit
import CoreServices
import ProfilesCore
import ProfilesUI

/// Receives `claude://` URLs while Claude Profiles is the registered handler and
/// forwards each to the instance the user is signing in (or asks which one).
/// The URL is held only in memory for the hand-off — never logged or stored.
@MainActor
final class CallbackBridge {
    static let shared = CallbackBridge()
    /// URLs that arrived before the scene finished launching (the app was started
    /// BY the callback). Drained once `handler` is set.
    private var queued: [URL] = []
    var handler: ((URL) -> Void)? {
        didSet {
            guard let handler else { return }
            let pending = queued
            queued = []
            pending.forEach(handler)
        }
    }
    func receive(_ url: URL) {
        guard url.scheme?.lowercased() == URLRouter.scheme else { return }
        if let handler { handler(url) } else { queued.append(url) }
    }
}

/// Registered before SwiftUI sees the event, so a callback never spawns a window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor,
                            withReplyEvent reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s) else { return }
        Task { @MainActor in CallbackBridge.shared.receive(url) }
    }
}

@MainActor
struct CallbackRouter {
    let store: StatsStore

    /// Resolve the running instances' PIDs, decide, and act.
    func route(_ url: URL) async {
        let target = await store.signInTarget()
        var running: [String: Int32] = [:]
        for stat in store.profiles where stat.running {
            if let pid = await store.mainPid(stat.effSlug) { running[stat.effSlug] = pid }
        }
        switch decideRoute(target: target, running: running) {
        case .forward(let slug, let pid):
            deliver(url, slug: slug, pid: pid)
            await store.clearSignInTarget()
        case .launchThenForward(let slug):
            // `signinroute` already launches the target; this covers a target
            // that was quit in the meantime. Wait for its process, then forward.
            await store.perform(slug == "default" ? ["opendefault"] : ["open", slug])
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let pid = await store.mainPid(slug) {
                    // Give the freshly launched app a moment to register its handler.
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    deliver(url, slug: slug, pid: pid)
                    await store.clearSignInTarget()
                    return
                }
            }
            alert("Couldn't reach that Claude",
                  "It didn't start in time, so the sign-in link wasn't delivered. Try Sign in again.")
        case .choose(let slugs):
            guard let slug = ask(slugs),
                  let pid = await store.mainPid(slug) else { return }
            deliver(url, slug: slug, pid: pid)
        case .noInstances:
            alert("No Claude is running",
                  "Use Sign in on a profile first, so the link has somewhere to go.")
        }
    }

    private func deliver(_ url: URL, slug: String, pid: Int32) {
        if !URLRouter.forward(url, toPID: pid) {
            alert("Couldn't deliver the sign-in link",
                  "macOS blocked Claude Profiles from controlling Claude. Allow it in System Settings, Privacy & Security, Automation, then Sign in again.")
        }
    }

    /// Which running instance should receive an un-targeted link?
    private func ask(_ slugs: [String]) -> String? {
        let a = NSAlert()
        a.messageText = "Open this link in which Claude?"
        a.informativeText = "More than one Claude is running."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26))
        for slug in slugs {
            let name = store.profiles.first { $0.effSlug == slug }?.name ?? slug
            popup.addItem(withTitle: name)
            popup.lastItem?.representedObject = slug
        }
        a.accessoryView = popup
        a.addButton(withTitle: "Open")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        return popup.selectedItem?.representedObject as? String
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
