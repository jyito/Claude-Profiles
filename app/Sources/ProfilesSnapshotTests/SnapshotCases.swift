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

        return cases
    }
}
