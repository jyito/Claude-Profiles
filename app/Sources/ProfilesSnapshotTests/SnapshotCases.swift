import SwiftUI
import ProfilesCore
import ProfilesUI

/// The registry of golden-PNG cases. Each Phase-2 task appends its view's cases
/// here. Kept separate from the harness so view tasks touch only this list.
@MainActor
enum SnapshotCases {
    static func all() -> [SnapshotCase] {
        var cases: [SnapshotCase] = []
        // Cases are registered by later tasks (BadgeDisc, StatusDot, Sparkline, …).
        return cases
    }
}
