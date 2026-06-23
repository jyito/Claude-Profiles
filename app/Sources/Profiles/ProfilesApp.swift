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
    /// The detail column's master-detail navigation stack. Empty = the overview
    /// (card grid / list); a single pushed slug = that profile's maximized detail
    /// page. Kept in sync with `selection` by `DashboardView`.
    @State private var navPath: [String] = []
    /// Detail layout: card grid (default) or the dense list. Toolbar-driven.
    @State private var viewMode: ProfileViewMode = .grid
    /// Which modal (if any) is presented. The scene owns this — the sheet views are
    /// pure and never call the engine themselves (CLAUDE.md non-negotiables).
    @State private var activeSheet: DashboardSheet?
    /// The loaded Remote info + display name, set by `presentRemote` before the
    /// Remote sheet opens (so the sheet renders already populated).
    @State private var loadedRemote: (name: String, info: RemoteInfo)?
    /// A card overflow action awaiting confirmation. Force Quit and Restart kill /
    /// cycle the user's live Claude, so they route through a `.confirmationDialog`
    /// before firing; graceful Quit fires directly (no pending). Cleared on confirm
    /// or cancel.
    @State private var pendingCardAction: PendingCardAction?

    var body: some Scene {
        WindowGroup("Claude Profiles") {
            NavigationSplitView {
                SidebarView(profiles: store.profiles, selection: $selection)
                    // Selecting a sidebar row pushes that profile's detail page;
                    // clearing it pops back to the grid. The selection→navPath sync
                    // lives in `DashboardView` so the grid's "Details ›" and the
                    // sidebar share one path.
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
                DashboardView(store: store, selection: $selection, navPath: $navPath,
                              viewMode: $viewMode,
                              onRemote: { slug in presentRemote(slug) },
                              onNewProfile: { activeSheet = .newProfile },
                              onCardAction: { action, slug in handleCardAction(action, slug) })
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
            .navigationSplitViewStyle(.balanced)
            // Freely resizable: a sensible minimum (sidebar + detail; the old 1000px
            // floor was for the retired 3-column inspector) and grow without limit.
            .frame(minWidth: 860, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
            .background(Theme.canvas)
            .preferredColorScheme(.dark)
            .onAppear { store.start() }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
            }
            // Disruptive card actions (Force Quit / Restart) confirm before firing.
            // Graceful Quit never reaches here — it fires directly in `handleCardAction`.
            .confirmationDialog(
                pendingCardAction?.title ?? "",
                isPresented: pendingDialogBinding,
                titleVisibility: .visible,
                presenting: pendingCardAction
            ) { pending in
                Button(pending.confirmLabel, role: pending.confirmRole) {
                    runCardAction(pending)
                }
                Button("Cancel", role: .cancel) { pendingCardAction = nil }
            } message: { pending in
                Text(pending.message)
            }
        }
        .windowToolbarStyle(.unified)
        // Min size follows the content's minimum, freely resizable above it.
        .windowResizability(.contentMinSize)

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

    // MARK: Card overflow (Restart / Quit / Force Quit)
    //
    // The scene owns the engine call (CLAUDE.md non-negotiables); the card just emits
    // the intent. Graceful Quit fires immediately; the disruptive pair (Force Quit /
    // Restart) route through a `.confirmationDialog` since they kill / cycle the user's
    // live Claude.

    /// Binding the `.confirmationDialog` reads: presented iff a pending action exists.
    /// Setting it false (Cancel / dismiss) clears the pending action.
    private var pendingDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingCardAction != nil },
            set: { if !$0 { pendingCardAction = nil } }
        )
    }

    /// Route a card's overflow action. Quit (graceful) fires straight away; Force Quit
    /// and Restart stash a `PendingCardAction` so the confirmationDialog gates them.
    @MainActor private func handleCardAction(_ action: CardAction, _ slug: String) {
        let stat = store.profiles.first { $0.effSlug == slug }
        let isDefault = stat?.isDefault ?? (slug == "default")
        let name = stat?.name ?? slug
        switch action {
        case .quit:
            // Graceful — no confirmation needed.
            let verbs = quitVerbs(slug: slug, isDefault: isDefault)
            Task { await store.perform(verbs) }
        case .force, .restart:
            pendingCardAction = PendingCardAction(
                action: action, slug: slug, name: name, isDefault: isDefault
            )
        }
    }

    /// Fire a confirmed (Force Quit / Restart) action, then clear the pending state.
    @MainActor private func runCardAction(_ pending: PendingCardAction) {
        let verbs: [String]
        switch pending.action {
        case .force: verbs = forceVerbs(slug: pending.slug, isDefault: pending.isDefault)
        case .restart: verbs = restartVerbs(slug: pending.slug, isDefault: pending.isDefault)
        case .quit: verbs = quitVerbs(slug: pending.slug, isDefault: pending.isDefault)
        }
        Task { await store.perform(verbs) }
        pendingCardAction = nil
    }

    // Engine verb mapping — the default instance is signal-only (`quitdefault` /
    // `forcedefault`), while `restart` accepts the literal `default` slug. Regular
    // profiles take their own slug. (Verbs confirmed in src/engine.sh dispatch.)
    private func quitVerbs(slug: String, isDefault: Bool) -> [String] {
        isDefault ? ["quitdefault"] : ["quit", slug]
    }
    private func forceVerbs(slug: String, isDefault: Bool) -> [String] {
        isDefault ? ["forcedefault"] : ["force", slug]
    }
    private func restartVerbs(slug: String, isDefault: Bool) -> [String] {
        isDefault ? ["restart", "default"] : ["restart", slug]
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

/// A card overflow action (Force Quit / Restart) awaiting confirmation. Carries the
/// resolved display name + the default-vs-regular flag so the dialog copy and the
/// engine verb mapping both read off one value. (Graceful Quit never becomes a
/// pending action — it fires without a dialog.)
struct PendingCardAction: Identifiable {
    let action: CardAction
    let slug: String
    let name: String
    let isDefault: Bool
    var id: String { "\(slug)-\(verbKey)" }

    private var verbKey: String {
        switch action {
        case .quit: return "quit"
        case .force: return "force"
        case .restart: return "restart"
        }
    }

    var title: String {
        switch action {
        case .force: return "Force-quit \(name)?"
        case .restart: return "Restart \(name)?"
        case .quit: return "Quit \(name)?"
        }
    }

    var message: String {
        switch action {
        case .force: return "Unsaved work in that Claude may be lost."
        case .restart: return "Its windows and terminals close and reopen; login and chats are kept."
        case .quit: return ""
        }
    }

    var confirmLabel: String {
        switch action {
        case .force: return "Force Quit"
        case .restart: return "Restart"
        case .quit: return "Quit"
        }
    }

    var confirmRole: ButtonRole? {
        action == .force ? .destructive : nil
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
