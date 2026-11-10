// Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
// See LICENSE and NOTICE in the repository root.
import Foundation

/// The engine's `signin <slug|default>` response: which instance the next
/// browser sign-in is routed to, and which running instances were closed so
/// the `claude://` callback has exactly one home.
public struct SignInResult: Codable, Sendable, Equatable {
    public let target: String
    public let closed: [String]

    public init(target: String, closed: [String]) {
        self.target = target
        self.closed = closed
    }

    public static func decode(from data: Data) throws -> SignInResult {
        try JSONDecoder().decode(SignInResult.self, from: data)
    }
}

/// Dashboard-side sign-in mode: non-nil while instances the engine closed for a
/// sign-in are waiting to be restored. `target` is nil when the mode was
/// recovered from a pending state file after an app relaunch (the engine only
/// persists what it closed, not who it closed it for).
public struct SignInMode: Sendable, Equatable {
    public let target: String?
    public let closed: [String]

    public init(target: String?, closed: [String]) {
        self.target = target
        self.closed = closed
    }
}

/// `signinrestore` payload: `{"restored":[…]}`.
struct SignInRestoredPayload: Codable { let restored: [String] }
/// `signinstate` payload: `{"pending":[…]}`.
struct SignInPendingPayload: Codable { let pending: [String] }
