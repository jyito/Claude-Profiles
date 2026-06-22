import SwiftUI
import ProfilesCore

/// Per-card render input: the stat, its rolling CPU/Mem series, and precomputed
/// AlertState. Deterministic — no time/env reads, so it snapshots stably.
public struct CardModel: Identifiable {
    public let stat: ProfileStat
    public let cpu: [Double]
    public let mem: [Double]
    public let state: AlertState
    public var id: String { stat.effSlug }

    public init(stat: ProfileStat, cpu: [Double], mem: [Double], state: AlertState) {
        self.stat = stat
        self.cpu = cpu
        self.mem = mem
        self.state = state
    }
}

/// The detail column content — the KPI strip + the adaptive card grid. Pure and
/// deterministic: the live `DashboardView` (in the app target) builds the
/// `CardModel`s from the store and hands them here, and the snapshot harness
/// builds them from fixtures. No store/clock/material reads here.
public struct DashboardContent: View {
    let profiles: [ProfileStat]
    let cards: [CardModel]
    let selection: String?
    let scrolls: Bool
    let onDetails: (String) -> Void

    /// `scrolls: false` is for snapshots — `ImageRenderer` does not lay out a
    /// `ScrollView`'s content (it renders empty), so the harness renders the bare
    /// VStack at a fixed frame. The live app uses the scrolling default.
    public init(profiles: [ProfileStat], cards: [CardModel], selection: String? = nil,
                scrolls: Bool = true, onDetails: @escaping (String) -> Void = { _ in }) {
        self.profiles = profiles
        self.cards = cards
        self.selection = selection
        self.scrolls = scrolls
        self.onDetails = onDetails
    }

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: Theme.Space.lg)]

    private var grid: some View {
        VStack(spacing: Theme.Space.lg) {
            KPIStripView(profiles: profiles)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.lg) {
                ForEach(cards) { m in
                    ProfileCardView(stat: m.stat, cpu: m.cpu, mem: m.mem,
                                    state: m.state, selected: selection == m.id,
                                    onDetails: onDetails)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: scrolls ? nil : .infinity, alignment: .top)
    }

    public var body: some View {
        Group {
            if scrolls {
                ScrollView { grid }
            } else {
                grid
            }
        }
        .background(Theme.canvas)
    }
}
