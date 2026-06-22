import SwiftUI
import ProfilesCore
import ProfilesUI

/// The registry of golden-PNG cases. Each Phase-2 task appends its view's cases
/// here. Kept separate from the harness so view tasks touch only this list.
@MainActor
enum SnapshotCases {
    static func all() -> [SnapshotCase] {
        var cases: [SnapshotCase] = []

        // Task 3 — BadgeDisc + StatusDot
        cases.append(SnapshotCase("badge-business", size: CGSize(width: 60, height: 60)) {
            BadgeDisc(name: "Business", colorHex: "#3B7DD8", slug: "business", size: 34)
        })
        cases.append(SnapshotCase("badge-default-lock", size: CGSize(width: 60, height: 60)) {
            BadgeDisc(name: "Claude (default)", colorHex: "#6E6A62", slug: "", size: 34, isDefault: true)
        })
        cases.append(SnapshotCase("dot-running", size: CGSize(width: 40, height: 40)) {
            StatusDot(running: true, size: 8)
        })
        cases.append(SnapshotCase("dot-stopped", size: CGSize(width: 40, height: 40)) {
            StatusDot(running: false, size: 8)
        })

        // Task 4 — Sparkline (Swift Charts)
        cases.append(SnapshotCase("spark-cpu", size: CGSize(width: 140, height: 44)) {
            Sparkline(values: Fixtures.cpuSeries, tint: Theme.cpuLine)
                .padding(.horizontal, 6)
        })
        cases.append(SnapshotCase("spark-mem", size: CGSize(width: 140, height: 44)) {
            Sparkline(values: Fixtures.memSeries, tint: Theme.memLine)
                .padding(.horizontal, 6)
        })
        cases.append(SnapshotCase("spark-ghost", size: CGSize(width: 140, height: 44)) {
            Sparkline.ghosted(Fixtures.cpuSeries)
                .padding(.horizontal, 6)
        })

        // Task 5 — running ProfileCard (calm) + warning gauge
        cases.append(SnapshotCase("card-running-business", size: CGSize(width: 340, height: 300)) {
            ProfileCardView(stat: Fixtures.business, cpu: Fixtures.cpuSeries,
                            mem: Fixtures.memSeries, state: .calm, selected: false)
                .padding(Theme.Space.lg)
        })
        cases.append(SnapshotCase("card-running-research-warning", size: CGSize(width: 340, height: 300)) {
            ProfileCardView(stat: Fixtures.research, cpu: Fixtures.cpuSeriesHot,
                            mem: Fixtures.memSeriesHot, state: .warning(climbing: true), selected: true)
                .padding(Theme.Space.lg)
        })

        // Task 6 — stopped + default ProfileCard variants
        cases.append(SnapshotCase("card-stopped-clientx", size: CGSize(width: 340, height: 250)) {
            ProfileCardView(stat: Fixtures.clientX, cpu: Fixtures.cpuSeries,
                            mem: Fixtures.memSeries, state: .calm, selected: false)
                .padding(Theme.Space.lg)
        })
        cases.append(SnapshotCase("card-default", size: CGSize(width: 340, height: 280)) {
            ProfileCardView(stat: Fixtures.defaultInstance, cpu: Fixtures.cpuSeries,
                            mem: Fixtures.memSeries, state: .calm, selected: false)
                .padding(Theme.Space.lg)
        })

        // Task 7 — KPI instrument strip
        cases.append(SnapshotCase("kpi-strip", size: CGSize(width: 820, height: 110)) {
            KPIStripView(profiles: Fixtures.all)
                .padding(Theme.Space.lg)
        })

        return cases
    }
}
