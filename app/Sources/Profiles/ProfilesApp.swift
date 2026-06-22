import SwiftUI
import ProfilesCore
import ProfilesUI

@main
struct ProfilesApp: App {
    @State private var store = StatsStore(
        engine: EngineClient(enginePath: resolveEnginePath()),
        clock: RealClock()
    )
    @State private var selection: String?
    @State private var inspectorShown = false
    /// Which modal (if any) is presented. The scene owns this — the sheet views are
    /// pure and never call the engine themselves (CLAUDE.md non-negotiables).
    @State private var activeSheet: DashboardSheet?

    var body: some Scene {
        WindowGroup("Claude Profiles") {
            NavigationSplitView {
                SidebarView(profiles: store.profiles, selection: $selection)
                    .onChange(of: selection) { _, new in
                        // Selecting a sidebar row opens the inspector; clearing it closes it.
                        inspectorShown = (new != nil)
                    }
                    .background(VisualEffectView())
                    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
                    .safeAreaInset(edge: .bottom) {
                        Button {
                            activeSheet = .newProfile
                        } label: {
                            Label("New Profile", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButtonStyle(.prominentCoral))
                        .padding(Theme.Space.md)
                        .accessibilityIdentifier("sidebar-new-profile")
                    }
            } detail: {
                DashboardView(store: store, selection: $selection, inspectorShown: $inspectorShown,
                              onRemote: { slug in presentRemote(slug) })
                    .navigationTitle("Profiles")
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Image(systemName: "square.on.square")
                                .foregroundStyle(Theme.coral)
                        }
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button { activeSheet = .cleanup } label: {
                                Label("Cleanup", systemImage: "trash")
                            }
                            .accessibilityIdentifier("toolbar-cleanup")

                            Button { presentSettings() } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                            .keyboardShortcut(",", modifiers: .command)
                            .accessibilityIdentifier("toolbar-settings")

                            Button { activeSheet = .newProfile } label: {
                                Label("New Profile", systemImage: "plus")
                            }
                            .keyboardShortcut("n", modifiers: .command)
                            .accessibilityIdentifier("toolbar-new-profile")
                        }
                    }
            }
            .frame(minWidth: 840, minHeight: 560)
            .background(Theme.canvas)
            .preferredColorScheme(.dark)
            .onAppear { store.start() }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
            }
        }
        .windowToolbarStyle(.unified)

        // Menu-bar switcher (live focus wiring is Phase 5 — a static list is fine).
        MenuBarExtra("Claude Profiles", systemImage: "square.on.square") {
            ForEach(store.profiles) { stat in
                Text(stat.name)
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    // MARK: Sheet routing
    //
    // The scene owns every engine call; the sheet views are pure (fixtures +
    // closures). Settings/Remote load their data BEFORE presenting so the sheet
    // opens already populated.

    @MainActor @ViewBuilder private func sheetContent(for sheet: DashboardSheet) -> some View {
        switch sheet {
        case .newProfile:
            NewProfileSheet(
                onCreate: { name in
                    activeSheet = nil
                    Task { await store.engineCreate(name) }
                },
                onCancel: { activeSheet = nil }
            )
        case .settings:
            SettingsSheet(
                config: store.config,
                onChange: { key, value in Task { await store.setConfig(key, value) } },
                onClose: { activeSheet = nil }
            )
        case .cleanup, .remote:
            // Filled in by Tasks 4, 6.
            EmptyView()
        }
    }

    @MainActor private func presentSettings() {
        Task {
            await store.loadConfig()
            activeSheet = .settings
        }
    }

    @MainActor private func presentRemote(_ slug: String) {
        // Task 6 loads remoteInfo before presenting; placeholder for now.
        activeSheet = .remote(slug)
    }
}

/// Which modal the dashboard scene is presenting. `Identifiable` so it drives
/// `.sheet(item:)` directly.
enum DashboardSheet: Identifiable {
    case newProfile
    case settings
    case cleanup
    case remote(String)   // the slug whose Remote sheet is open

    var id: String {
        switch self {
        case .newProfile: return "newProfile"
        case .settings: return "settings"
        case .cleanup: return "cleanup"
        case .remote(let slug): return "remote-\(slug)"
        }
    }
}
