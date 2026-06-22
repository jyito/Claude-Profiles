import Foundation
import Observation

@MainActor
@Observable
public final class StatsStore {
    public private(set) var profiles: [ProfileStat] = []
    public private(set) var terminals: [TerminalInfo] = []
    public private(set) var config = ProfileConfig()
    public private(set) var lastError: String?

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
