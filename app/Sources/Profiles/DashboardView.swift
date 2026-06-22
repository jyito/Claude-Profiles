import SwiftUI
import ProfilesCore
import ProfilesUI

/// The live detail column. Keeps a rolling 30-point CPU/Mem history per slug and
/// a per-slug `PtmxHysteresis` (persisted across ticks in `@State` dictionaries
/// keyed by slug), feeds the latest sample each tick, and builds the deterministic
/// `DashboardContent`. The store re-renders this every 2s.
@MainActor
struct DashboardView: View {
    let store: StatsStore
    let selection: String?

    @State private var cpuHistory: [String: [Double]] = [:]
    @State private var memHistory: [String: [Double]] = [:]
    @State private var hysteresis: [String: PtmxHysteresis] = [:]
    @State private var states: [String: AlertState] = [:]

    private static let historyLen = 30

    var body: some View {
        DashboardContent(profiles: store.profiles, cards: cards, selection: selection)
            .onChange(of: store.profiles) { _, fresh in
                ingest(fresh)
            }
            .onAppear { ingest(store.profiles) }
    }

    private var cards: [CardModel] {
        store.profiles.map { stat in
            CardModel(
                stat: stat,
                cpu: cpuHistory[stat.effSlug] ?? [stat.cpu],
                mem: memHistory[stat.effSlug] ?? [stat.mem],
                state: states[stat.effSlug] ?? .calm
            )
        }
    }

    private func ingest(_ fresh: [ProfileStat]) {
        for stat in fresh {
            let key = stat.effSlug
            // rolling CPU/Mem
            var c = cpuHistory[key] ?? []
            c.append(stat.cpu)
            if c.count > Self.historyLen { c.removeFirst(c.count - Self.historyLen) }
            cpuHistory[key] = c

            var m = memHistory[key] ?? []
            m.append(stat.mem)
            if m.count > Self.historyLen { m.removeFirst(m.count - Self.historyLen) }
            memHistory[key] = m

            // per-slug hysteresis severity (default instance never leak-alerts in UI,
            // but the engine still emits ptmx; feeding it is harmless and consistent)
            var h = hysteresis[key] ?? PtmxHysteresis()
            states[key] = h.ingest(PtmxSample(used: stat.ptmx, max: stat.ptmxMax))
            hysteresis[key] = h
        }
    }
}
