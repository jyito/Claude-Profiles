import SwiftUI
import ProfilesCore
import ProfilesUI

/// The live detail column. Keeps a rolling ~60-point CPU/Mem/ptmx history per slug
/// (≈2 min at the 2s tick — long enough that the detail-page hero trends read
/// clearly; the card sparklines lengthen too, which is fine) and a per-slug
/// `PtmxHysteresis` (persisted across ticks in `@State` dictionaries keyed by slug),
/// feeds the latest sample each tick, and builds the deterministic `DashboardContent`.
/// The store re-renders this every 2s.
///
/// Master-detail (replacing the old `.inspector` 3rd column): the content lives in
/// a `NavigationStack(path:)` whose root is the card grid / list and whose
/// `String`-keyed destination is the maximized `ProfileDetailView`. A card's
/// "Details ›" or a sidebar selection pushes the slug; the system back button pops
/// to the grid. `navPath` and `selection` are kept in sync so the sidebar highlight
/// and the pushed page always agree (and back-to-grid clears the selection).
@MainActor
struct DashboardView: View {
    let store: StatsStore
    @Binding var selection: String?
    /// The detail column's navigation stack. Empty = overview (grid/list); a single
    /// pushed slug = that profile's maximized detail page.
    @Binding var navPath: [String]
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
    @State private var ptmxHistory: [String: [Double]] = [:]
    @State private var hysteresis: [String: PtmxHysteresis] = [:]
    @State private var states: [String: AlertState] = [:]

    // ~2 min of history at the 2s tick — long enough that the detail-page hero
    // trends read clearly (also lengthens the card sparklines, intentionally).
    private static let historyLen = 60

    var body: some View {
        NavigationStack(path: $navPath) {
            detailContent
                .navigationDestination(for: String.self) { slug in
                    profileDetail(for: slug)
                }
        }
        // Inactive-window dim: a subtle whole-pane fade when the window loses key.
        .opacity(appearsActive ? 1 : 0.85)
        .onChange(of: store.profiles) { _, fresh in
            ingest(fresh)
        }
        .onAppear { ingest(store.profiles) }
        // Sidebar selection drives the push; clearing it pops to the grid. Guarded so
        // it doesn't fight the back button (which already mutates navPath → selection).
        .onChange(of: selection) { _, slug in
            let desired = slug.map { [$0] } ?? []
            if navPath != desired { navPath = desired }
        }
        // The system back button pops navPath; mirror that back into selection so the
        // sidebar highlight clears (and a re-selection re-pushes cleanly).
        .onChange(of: navPath) { _, path in
            let top = path.last
            if selection != top { selection = top }
        }
        // Load the pushed instance's terminals whenever the open profile changes.
        .task(id: navPath.last) {
            if let slug = navPath.last,
               store.profiles.contains(where: { $0.effSlug == slug }) {
                await store.loadTerminals(for: slug)
            }
        }
    }

    /// Open a profile's maximized detail page (sidebar row OR card "Details ›").
    private func open(_ slug: String) {
        if navPath.last != slug { navPath = [slug] }
    }

    /// State gating, then Grid vs List. The decision lives in `dashboardMode` (pure +
    /// unit-tested in ProfilesCore) so the empty-state gate can't regress to dead
    /// code: the engine always emits the default instance, so the onboarding state
    /// must key off "only the default exists", not "no profiles". This is the
    /// `NavigationStack` ROOT — the grid/list overview. The toolbar Grid/List toggle
    /// applies here; opening a profile pushes `ProfileDetailView` on top.
    @ViewBuilder private var detailContent: some View {
        switch dashboardMode(profiles: store.profiles, hasLoadedOnce: store.hasLoadedOnce) {
        case .loading:
            LoadingSkeletonView()
        case .empty:
            EmptyStateView(onNewProfile: onNewProfile)
        case .content:
            liveContent
        }
    }

    @ViewBuilder private var liveContent: some View {
        switch viewMode {
        case .grid:
            DashboardContent(profiles: store.profiles, cards: cards, selection: selection,
                             onDetails: { open($0) },
                             onRemote: onRemote,
                             onShowWindow: showWindow,
                             onOpen: { slug in Task { await store.perform(["open", slug]) } })
        case .list:
            // A row selection pushes that profile's detail page (matching the grid's
            // Details tap). `selection` → `navPath` is wired in `body`'s onChange.
            ProfileListView(profiles: store.profiles, selection: $selection)
        }
    }

    /// Build the maximized detail page for a pushed slug. Resolves the live stat; a
    /// vanished slug (deleted while open) falls back to a quiet placeholder so the
    /// pushed view never crashes on a missing profile.
    @ViewBuilder private func profileDetail(for slug: String) -> some View {
        if let stat = store.profiles.first(where: { $0.effSlug == slug }) {
            ProfileDetailView(
                stat: stat,
                cpu: cpuHistory[stat.effSlug] ?? [stat.cpu],
                mem: memHistory[stat.effSlug] ?? [stat.mem],
                ptmx: ptmxHistory[stat.effSlug] ?? [Double(stat.ptmx)],
                state: states[stat.effSlug] ?? .calm,
                terminals: store.terminals,
                onShowWindow: showWindow,
                onRemote: onRemote,
                onOpen: { s in Task { await store.perform(["open", s]) } },
                onAction: { handle($0, for: stat) }
            )
        } else {
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

    // MARK: Drill-down actions

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
                // Both `remove` and `purge` must succeed before we pop: a failed
                // `purge` may have orphaned the (precious) data dir, so keep the
                // detail page open and let `store.lastError` surface it. Return early —
                // never `loadTerminals` against the just-deleted slug; popping the
                // stack (on success) re-routes back to the grid.
                if await store.removeProfile(slug) {
                    navPath = []
                    selection = nil
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

            // rolling leaked-handle (ptmx) series — feeds the detail handle trend.
            var p = ptmxHistory[key] ?? []
            p.append(Double(stat.ptmx))
            if p.count > Self.historyLen { p.removeFirst(p.count - Self.historyLen) }
            ptmxHistory[key] = p

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
        cpuHistory  = cpuHistory.filter  { live.contains($0.key) }
        memHistory  = memHistory.filter  { live.contains($0.key) }
        ptmxHistory = ptmxHistory.filter { live.contains($0.key) }
        hysteresis  = hysteresis.filter  { live.contains($0.key) }
        states      = states.filter      { live.contains($0.key) }
    }
}
