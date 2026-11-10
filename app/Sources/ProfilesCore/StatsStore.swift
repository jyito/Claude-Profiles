import Foundation
import Observation

@MainActor
@Observable
public final class StatsStore {
    public private(set) var profiles: [ProfileStat] = []
    public private(set) var terminals: [TerminalInfo] = []
    public private(set) var config = ProfileConfig()
    public private(set) var lastError: String?
    /// False until the first `refreshOnce` completes (success OR error) — drives the
    /// loading skeleton so the grid fills in rather than popping in from empty. Once
    /// true it stays true (a later bad tick keeps the last-good UI, never reverts to
    /// the skeleton).
    public private(set) var hasLoadedOnce = false

    private let engine: any EngineRunning
    private let clock: any PollClock
    private var task: Task<Void, Never>?

    public nonisolated init(engine: any EngineRunning, clock: any PollClock) {
        self.engine = engine
        self.clock = clock
    }

    public func refreshOnce() async {
        do {
            let fresh = try await engine.stats()
            profiles = sortProfiles(fresh)
            lastError = nil
        } catch {
            lastError = String(describing: error)   // keep last-good profiles — don't blank the UI on one bad tick
        }
        // The first tick is done (even if it failed) — drop the loading skeleton so a
        // persistent error doesn't shimmer forever. Set once; never reverts.
        hasLoadedOnce = true
    }

    /// Load the terminals drill-down for one instance. A failed load empties
    /// `terminals` rather than leaving a stale list under the inspector.
    public func loadTerminals(for slug: String) async {
        do { terminals = try await engine.terminals(slug) }
        catch { terminals = [] }
    }

    /// Fire an engine action (the inspector's `onAction` sink maps to this), then
    /// refresh stats so the UI reflects the result. Returns whether the action
    /// succeeded; on failure the error is surfaced via `lastError` and the
    /// last-good profiles are kept (the refresh never blanks the UI on one bad tick).
    @discardableResult
    public func perform(_ args: [String]) async -> Bool {
        var ok = true
        do { try await engine.run(args) }
        catch {
            lastError = String(describing: error)
            ok = false
        }
        await refreshOnce()
        return ok
    }

    /// Load the two opt-in automation knobs for the Settings sheet. A failed load
    /// keeps the last-known config (and surfaces the error) rather than resetting it.
    public func loadConfig() async {
        do {
            config = try await engine.getConfig()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Persist one config key, then optimistically mirror it into `config` so the
    /// open Settings sheet reflects the change without a reload. On engine error
    /// (`err badkey`/`err badval`) the value is NOT mirrored and the error surfaces.
    @discardableResult
    public func setConfig(_ key: String, _ value: Int) async -> Bool {
        do {
            try await engine.setConfig(key, value)
            switch ProfileConfig.Key(rawValue: key) {
            case .autoCleanThresholdMB: config.autoCleanThresholdMB = value
            case .autoCloseIdleMin: config.autoCloseIdleMin = value
            case .autoRestartLeakAt: config.autoRestartLeakAt = value
            case .none: break
            }
            lastError = nil
            return true
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    /// Create a profile wrapper, then refresh stats so the new card appears. Returns
    /// the engine-derived slug on success (the slug differs from the raw name), or
    /// nil on failure (the error is surfaced via `lastError`).
    @discardableResult
    public func engineCreate(_ name: String) async -> String? {
        do {
            let slug = try await engine.create(name)
            lastError = nil
            await refreshOnce()
            return slug
        } catch {
            lastError = String(describing: error)
            await refreshOnce()
            return nil
        }
    }

    /// Load a profile's Remote-access info for the Remote sheet (starts/reuses its
    /// Claude Code `screen` session). On a transport error returns a `RemoteInfo`
    /// carrying the error message so the sheet always has something to show.
    public func remoteInfo(for slug: String) async -> RemoteInfo {
        do {
            let info = try await engine.remoteInfo(slug)
            lastError = info.error
            return info
        } catch {
            let msg = String(describing: error)
            lastError = msg
            return RemoteInfo(slug: slug, session: "", user: "", host: "",
                              tailscaleIp: "", alreadyRunning: false, error: msg)
        }
    }

    /// Stop a profile's Claude Code `screen` session (Remote sheet's "Stop
    /// session" button). Idempotent; the next stats tick clears the card's live
    /// dot. Errors surface via `lastError`.
    public func remoteStop(_ slug: String) async {
        do { try await engine.remoteStop(slug); lastError = nil }
        catch { lastError = String(describing: error) }
    }

    /// Resolve an instance's main PID for in-process focus (Show Window / the
    /// menu-bar switcher). Returns nil if not running (or on a transport error,
    /// surfaced via `lastError`) — the caller no-ops rather than focusing pid 0.
    public func mainPid(_ slug: String) async -> Int32? {
        do {
            let pid = try await engine.mainPid(slug)
            lastError = nil
            return pid
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    /// Copy text to the clipboard (Remote sheet's Copy buttons).
    public func copy(_ text: String) async {
        do { try await engine.copy(text); lastError = nil }
        catch { lastError = String(describing: error) }
    }

    // MARK: Sign-in routing

    /// Non-nil while instances the engine closed for a sign-in await restore —
    /// drives the dashboard's sign-in banner.
    public private(set) var signInMode: SignInMode?

    /// Route the next browser sign-in to `slug`: the engine closes the other
    /// running instances and ensures the target is up. Enters sign-in mode only
    /// when something was actually closed — with nothing else running the
    /// `claude://` callback is already unambiguous, so no banner.
    @discardableResult
    public func beginSignIn(_ slug: String) async -> Bool {
        do {
            let result = try await engine.signIn(slug)
            signInMode = result.closed.isEmpty
                ? nil
                : SignInMode(target: result.target, closed: result.closed)
            lastError = nil
            await refreshOnce()
            return true
        } catch {
            lastError = String(describing: error)
            await refreshOnce()
            return false
        }
    }

    /// Reopen everything the sign-in closed, then leave sign-in mode. On engine
    /// failure the mode is KEPT so the banner (and the user's way back) survives.
    public func restoreSignIn() async {
        do {
            _ = try await engine.signInRestore()
            signInMode = nil
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
        await refreshOnce()
    }

    /// Dismiss the banner without reopening anything (drops the engine's pending
    /// restore list too, so it doesn't resurface on the next launch).
    public func dismissSignIn() async {
        do {
            try await engine.signInClear()
            signInMode = nil
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Startup probe: after an app relaunch mid-sign-in the engine still holds
    /// the restore list — re-enter sign-in mode (target unknown) so Restore is
    /// re-offered. Best-effort: a probe failure is silent (no lastError), the
    /// regular tick will surface real engine trouble.
    public func checkSignInPending() async {
        guard let pending = try? await engine.signInState(), !pending.isEmpty else { return }
        signInMode = SignInMode(target: nil, closed: pending)
    }

    /// The tty of a Terminal window already attached to `slug`'s Claude Code
    /// session, for the window stacker. nil = none attached (or transport error,
    /// surfaced via `lastError`) — the stacker opens a fresh window instead.
    public func remoteTty(_ slug: String) async -> String? {
        do { return try await engine.remoteTty(slug) }
        catch { lastError = String(describing: error); return nil }
    }

    /// Remove a profile: `remove` (delete the wrapper) THEN `purge` (delete its
    /// data dir). The data dir is precious (CLAUDE.md §6), so only report success
    /// when BOTH steps succeed — a failed `purge` (orphaned data dir) must be
    /// visible, not silent. Returns `true` only if both engine calls succeeded.
    public func removeProfile(_ slug: String) async -> Bool {
        do {
            try await engine.run(["remove", slug])
            try await engine.run(["purge", slug])
            lastError = nil
            await refreshOnce()
            return true
        } catch {
            lastError = String(describing: error)
            await refreshOnce()
            return false
        }
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            // One-shot: recover a sign-in restore pending from a previous run
            // before the regular tick loop begins.
            await self?.checkSignInPending()
            while !Task.isCancelled {
                // Bail if the store has been deinited — optional-chained no-ops
                // would otherwise busy-spin (the while condition stays true).
                guard let self else { return }
                await self.refreshOnce()
                await self.clock.sleepTick()
            }
        }
    }

    public func stop() { task?.cancel(); task = nil }
}
