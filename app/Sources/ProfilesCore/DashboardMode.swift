import Foundation

/// Which top-level state the dashboard detail column should show. Extracted as a
/// pure function (out of the SwiftUI view) so the gate is unit-testable and can't
/// silently regress to dead code.
public enum DashboardMode: Equatable {
    /// The first stats tick hasn't landed yet → loading skeleton.
    case loading
    /// No USER-created profiles yet (only the always-present default instance) →
    /// the onboarding empty state. The default stays reachable via the sidebar's
    /// "System" row; this is the intended fresh-install look.
    case empty
    /// At least one user profile exists → the live grid/list.
    case content
}

/// Decide the dashboard mode from the roster + load flag. The engine ALWAYS emits
/// the default instance, so `profiles.isEmpty` is never true in practice — the
/// empty state must key off "every profile is the default", not "no profiles".
public func dashboardMode(profiles: [ProfileStat], hasLoadedOnce: Bool) -> DashboardMode {
    if !hasLoadedOnce { return .loading }
    // Only the always-present default (or a vacuously empty array) → no user
    // profiles yet → onboarding. `allSatisfy` is vacuously true for [].
    if profiles.allSatisfy(\.isDefault) { return .empty }
    return .content
}
