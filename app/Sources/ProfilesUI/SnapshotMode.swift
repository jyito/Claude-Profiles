import SwiftUI

/// When true, views render deterministically for `ImageRenderer` golden PNGs:
/// no breathing pulse, no `.animation`, plain (non-`contentTransition`) numbers.
/// Threaded through `.environment(\.snapshotMode, true)` by the snapshot harness.
public struct SnapshotModeKey: EnvironmentKey {
    public static let defaultValue = false
}

public extension EnvironmentValues {
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}
