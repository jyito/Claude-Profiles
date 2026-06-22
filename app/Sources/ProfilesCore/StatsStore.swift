import Foundation
import Observation

@MainActor
@Observable
public final class StatsStore {
    public private(set) var profiles: [ProfileStat] = []
    public private(set) var terminals: [TerminalInfo] = []
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
    /// refresh stats so the UI reflects the result. Errors are surfaced via
    /// `lastError`; a failed action never blanks the last-good profiles.
    public func perform(_ args: [String]) async {
        do { try await engine.run(args) }
        catch { lastError = String(describing: error) }
        await refreshOnce()
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
