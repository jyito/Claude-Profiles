// Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
// See LICENSE and NOTICE in the repository root.
import Foundation

/// What the callback router does with an incoming `claude://` URL.
public enum RouteDecision: Sendable, Equatable {
    /// The target instance is running: hand the URL to this process.
    case forward(slug: String, pid: Int32)
    /// A target was chosen (Sign in…) but is not running yet: launch it, wait for
    /// its process, then forward.
    case launchThenForward(slug: String)
    /// No target was chosen and several instances are running: ask the user.
    /// Slugs only, default first, then alphabetical.
    case choose([String])
    /// Nothing is running and nobody was chosen: there is nowhere to send it.
    case noInstances
}

/// Pure routing policy. `target` is the pending sign-in target (nil when none was
/// chosen, or it expired); `running` maps each running instance's slug (`default`
/// for the default instance) to its main PID. The URL itself is deliberately NOT
/// an input: the callback carries an auth code, and the policy never needs to look
/// at it.
public func decideRoute(target: String?, running: [String: Int32]) -> RouteDecision {
    if let target {
        if let pid = running[target] { return .forward(slug: target, pid: pid) }
        return .launchThenForward(slug: target)
    }
    switch running.count {
    case 0: return .noInstances
    case 1:
        let only = running.first!
        return .forward(slug: only.key, pid: only.value)
    default:
        let slugs = running.keys.sorted { a, b in
            if a == "default" { return true }
            if b == "default" { return false }
            return a < b
        }
        return .choose(slugs)
    }
}

/// `signinroute` / `signintarget` payload: `{"target":"slug"}` or `{"target":null}`.
struct SignInTargetPayload: Codable { let target: String? }
