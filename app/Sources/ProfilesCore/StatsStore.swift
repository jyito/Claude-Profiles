import Foundation
import Observation

@MainActor
@Observable
public final class StatsStore {
    public private(set) var profiles: [ProfileStat] = []
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
