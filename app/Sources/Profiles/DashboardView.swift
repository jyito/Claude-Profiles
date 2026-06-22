import SwiftUI
import ProfilesCore
import ProfilesUI

/// The live detail column. Keeps a rolling 30-point CPU/Mem history per slug and
/// a per-slug `PtmxHysteresis` (persisted across ticks in `@State` dictionaries
/// keyed by slug), feeds the latest sample each tick, and builds the deterministic
/// `DashboardContent`. The store re-renders this every 2s. Also hosts the right-side
/// `.inspector` drill-down — opening it never reflows the grid (the design's bet).
@MainActor
struct DashboardView: View {
    let store: StatsStore
    @Binding var selection: String?
    @Binding var inspectorShown: Bool
    /// Grid (cards) vs List (dense table); driven by the toolbar segmented control.
    @Binding var viewMode: ProfileViewMode
    /// Called when a card's Remote button is tapped (scene presents the Remote sheet).
    var onRemote: (String) -> Void = { _ in }
    /// Open the New Profile sheet (the empty-state CTA routes here, same as the toolbar).
    var onNewProfile: () -> Void = {}

    /// Dim the detail content when the window isn't key/active — a quiet inactive
    /// tell, matching macOS sidebar/material behavior. `\.controlActiveState`
    /// (`.key`/`.active`/`.inactive`) is the SDK-14 portable signal; macOS 15's
    /// `\.appearsActive` (the plan's reference) isn't in this toolchain's SDK.
    @Environment(\.controlActiveState) private var controlActiveState

    private var appearsActive: Bool { controlActiveState != .inactive }

    @State private var cpuHistory: [String: [Double]] = [:]
    @State private var memHistory: [String: [Double]] = [:]
    @State private var hysteresis: [String: PtmxHysteresis] = [:]
    @State private var states: [String: AlertState] = [:]

    private static let historyLen = 30

    var body: some View {
        detailContent
            // Inactive-window dim: a subtle whole-pane fade when the window loses key.
            .opacity(appearsActive ? 1 : 0.85)
            .onChange(of: store.profiles) { _, fresh in
                ingest(fresh)
            }
            .onAppear { ingest(store.profiles) }
            .inspector(isPresented: $inspectorShown) {
                inspectorContent
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
            // Load the selected instance's terminals whenever selection changes.
            .task(id: selection) {
                if let slug = selectedStat?.effSlug {
                    await store.loadTerminals(for: slug)
                }
            }
    }

    /// State gating, then Grid vs List. The loading skeleton shows until the first
    /// stats tick lands; an empty roster shows the empty state; otherwise the live
    /// grid/list (both feed `selection`, so flipping view mode keeps the inspector).
    @ViewBuilder private var detailContent: some View {
        if !store.hasLoadedOnce {
            LoadingSkeletonView()
        } else if store.profiles.isEmpty {
            EmptyStateView(onNewProfile: onNewProfile)
        } else {
            liveContent
        }
    }

    @ViewBuilder private var liveContent: some View {
        switch viewMode {
        case .grid:
            DashboardContent(profiles: store.profiles, cards: cards, selection: selection,
                             onDetails: { slug in
                                 selection = slug
                                 inspectorShown = true
                             },
                             onRemote: onRemote,
                             onShowWindow: showWindow,
                             onOpen: { slug in Task { await store.perform(["open", slug]) } })
        case .list:
            ProfileListView(profiles: store.profiles, selection: $selection)
                .onChange(of: selection) { _, new in
                    // A row selection opens the inspector (matching the grid's Details tap).
                    inspectorShown = (new != nil)
                }
        }
    }

    // MARK: Show Window (in-process focus)

    /// Resolve the instance's main PID, then raise its windows in-process. This is
    /// the IN-PROCESS path (NSRunningApplication + a System Events fallback) — it does
    /// NOT shell `engine focus`. Targets the PID, never the shared bundle id. A
    /// stopped instance resolves to nil → no-op (its card shows Open, not Show Window).
    private func showWindow(_ slug: String) {
        Task {
            if let pid = await store.mainPid(slug) {
                Focus.show(pid: pid)
            }
        }
    }

    // MARK: Inspector

    private var selectedStat: ProfileStat? {
        guard let selection else { return nil }
        return store.profiles.first { $0.effSlug == selection }
    }

    @ViewBuilder private var inspectorContent: some View {
        if let stat = selectedStat {
            InspectorView(
                stat: stat,
                terminals: store.terminals,
                state: states[stat.effSlug] ?? .calm,
                onAction: { handle($0, for: stat) }
            )
        } else {
            // No selection: a quiet placeholder rather than an empty pane.
            VStack {
                Spacer()
                Text("Select a profile")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text3)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        }
    }

    /// Map an inspector action to the engine, then refresh stats + terminals. The
    /// view stays pure; the scene owns every engine call (CLAUDE.md non-negotiables).
    private func handle(_ action: InspectorAction, for stat: ProfileStat) {
        let slug = stat.effSlug
        Task {
            switch action {
            case .closeTerminal(let dev):
                await store.perform(["closeterm", slug, dev])
            case .throttle:
                await store.perform(["throttle", slug])
            case .restart:
                await store.perform(["restart", slug])
            case .clean(let tier):
                await store.perform(["clean", slug, tier])
            case .setBadge(let index):
                await store.perform(["setbadge", slug, String(index)])
            case .remove:
                // Both `remove` and `purge` must succeed before we collapse: a failed
                // `purge` may have orphaned the (precious) data dir, so keep the
                // inspector open and let `store.lastError` surface it. Return early —
                // never `loadTerminals` against the just-deleted slug; the selection
                // change (on success) already triggers `.task(id: selection)`.
                if await store.removeProfile(slug) {
                    selection = nil
                    inspectorShown = false
                }
                return
            }
            // Keep the open terminals table fresh after an action.
            await store.loadTerminals(for: slug)
        }
    }

    // MARK: Card models

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

        // Prune per-slug state for profiles that have disappeared (deleted /
        // transient slug) so these dicts can't grow unbounded over the window's
        // lifetime. Render is unaffected (it maps over store.profiles).
        let live = Set(fresh.map(\.effSlug))
        cpuHistory = cpuHistory.filter { live.contains($0.key) }
        memHistory = memHistory.filter { live.contains($0.key) }
        hysteresis = hysteresis.filter { live.contains($0.key) }
        states     = states.filter     { live.contains($0.key) }
    }
}
