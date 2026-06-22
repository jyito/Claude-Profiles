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
    /// Detail layout: card grid (default) or the dense list. Toolbar-driven.
    @State private var viewMode: ProfileViewMode = .grid
    /// Which modal (if any) is presented. The scene owns this — the sheet views are
    /// pure and never call the engine themselves (CLAUDE.md non-negotiables).
    @State private var activeSheet: DashboardSheet?
    /// The loaded Remote info + display name, set by `presentRemote` before the
    /// Remote sheet opens (so the sheet renders already populated).
    @State private var loadedRemote: (name: String, info: RemoteInfo)?

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
                              viewMode: $viewMode,
                              onRemote: { slug in presentRemote(slug) })
                    .navigationTitle("Profiles")
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Image(systemName: "square.on.square")
                                .foregroundStyle(Theme.coral)
                        }
                        ToolbarItem(placement: .principal) {
                            Picker("View", selection: $viewMode) {
                                ForEach(ProfileViewMode.allCases) { mode in
                                    Image(systemName: mode.symbol)
                                        .accessibilityLabel(mode.label)
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("toolbar-viewmode")
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

        // Menu-bar switcher. Shares the one `@Observable StatsStore` with the window,
        // so the running dots match by construction (no second poll loop). Rebuilds
        // from `store.profiles` each open; tapping a row raises that instance's
        // windows in-process (focus by PID — never the shared bundle id). The
        // template SF Symbol tints to the menu bar automatically.
        MenuBarExtra("Claude Profiles", systemImage: "square.on.square") {
            ForEach(sortProfiles(store.profiles)) { stat in
                Button {
                    focusInstance(stat.effSlug)
                } label: {
                    // `.menu` style renders these as native menu items; the running
                    // state reads as a mint-dot suffix (custom swatches don't survive
                    // the native menu), keeping the tell consistent with the window.
                    Text(stat.running ? "\(stat.name)  ●" : stat.name)
                }
                .accessibilityIdentifier("menubar-row-\(stat.effSlug)")
            }
            Divider()
            Button("New Profile") { activeSheet = .newProfile }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("menubar-new-profile")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityIdentifier("menubar-quit")
        }
    }

    /// Resolve an instance's main PID and raise its windows in-process (shared by the
    /// menu-bar switcher). Stopped instances resolve to nil → no-op.
    @MainActor private func focusInstance(_ slug: String) {
        Task {
            if let pid = await store.mainPid(slug) {
                Focus.show(pid: pid)
            }
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
        case .cleanup:
            CleanupSheet(
                onAction: { action in
                    let verb: String
                    switch action {
                    case .quitAll: verb = "quitall"
                    case .cleanAll: verb = "cleanall"
                    case .emergencyStop: verb = "killswitch"
                    }
                    Task { await store.perform([verb]) }
                },
                onClose: { activeSheet = nil }
            )
        case .remote:
            if let loaded = loadedRemote {
                RemoteSheet(
                    name: loaded.name,
                    info: loaded.info,
                    onCopy: { text in Task { await store.copy(text) } },
                    onClose: { activeSheet = nil }
                )
            } else {
                EmptyView()
            }
        }
    }

    @MainActor private func presentSettings() {
        Task {
            await store.loadConfig()
            activeSheet = .settings
        }
    }

    @MainActor private func presentRemote(_ slug: String) {
        // Load the connect info (starts/reuses the screen session) BEFORE presenting
        // so the sheet opens already populated. The display name comes from the
        // matching profile (the engine's RemoteInfo carries only the slug).
        let name = store.profiles.first { $0.effSlug == slug }?.name ?? slug
        Task {
            let info = await store.remoteInfo(for: slug)
            loadedRemote = (name, info)
            activeSheet = .remote(slug)
        }
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
