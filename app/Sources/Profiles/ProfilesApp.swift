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

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Whether Claude Profiles is the registered `claude://` handler (the router).
    @State private var routingEnabled = URLRouter.isEnabled()

    var body: some Scene {
        WindowGroup("Claude Profiles") {
            // Tile-first: no sidebar. The overview is the card grid or the list;
            // a card's "Details ›" (or a list row) pushes the detail page.
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
                        Menu {
                            Button("Desktop windows") { arrange(.desktop) }
                            Button("Terminals") { arrange(.terminals) }
                            Divider()
                            Button("Everything") { arrange(.both) }
                        } label: {
                            Label("Stack", systemImage: "rectangle.split.2x1")
                        }
                        .accessibilityIdentifier("toolbar-stack")
                        .pointerCursor()

                        Button { activeSheet = .cleanup } label: {
                            Label("Cleanup", systemImage: "trash")
                        }
                        .accessibilityIdentifier("toolbar-cleanup")
                        .pointerCursor()

                        Button { presentSettings() } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .keyboardShortcut(",", modifiers: .command)
                        .accessibilityIdentifier("toolbar-settings")
                        .pointerCursor()

                        Button { activeSheet = .newProfile } label: {
                            Label("New Profile", systemImage: "plus")
                        }
                        .keyboardShortcut("n", modifiers: .command)
                        .accessibilityIdentifier("toolbar-new-profile")
                        .pointerCursor()
                    }
                }
            .frame(minWidth: 640, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
            .background(Theme.canvas)
            .preferredColorScheme(.dark)
            .onAppear {
                routingEnabled = URLRouter.isEnabled()
                store.start()
                // Deliver `claude://` links (and any that launched us) to the router.
                let routed = store
                CallbackBridge.shared.handler = { url in
                    Task { @MainActor in await CallbackRouter(store: routed).route(url) }
                }
            }
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
            Menu("Sign in with…") {
                ForEach(sortProfiles(store.profiles)) { stat in
                    Button(stat.name) { signIn(stat.effSlug, name: stat.name) }
                        .accessibilityIdentifier("menubar-signin-\(stat.effSlug)")
                }
            }
            Button("Stack Windows") { arrange(.desktop) }
                .accessibilityIdentifier("menubar-stack")
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
        case .signIn:
            signIn(slug, name: name)
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
        case .quit, .signIn: verbs = quitVerbs(slug: pending.slug, isDefault: pending.isDefault)
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

    // MARK: Sign in

    /// Sign in with `slug`'s account. With the router on, nothing is closed: the
    /// target is recorded, started if needed, and brought forward — the router sends
    /// the browser callback to it. With the router off, fall back to closing the other
    /// running Claudes (after a confirmation) so the callback has one home.
    @MainActor private func signIn(_ slug: String, name: String) {
        if routingEnabled {
            Task {
                if await store.routeSignIn(slug), let pid = await store.mainPid(slug) {
                    Focus.show(pid: pid)
                }
            }
            return
        }
        let others = store.profiles.filter { $0.running && $0.effSlug != slug }
        guard !others.isEmpty else {
            // Nothing else running: the callback is unambiguous already.
            Task {
                await store.beginSignIn(slug)
                if let pid = await store.mainPid(slug) { Focus.show(pid: pid) }
            }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Sign in to \(name)?"
        alert.informativeText = "macOS sends the browser login to only one running Claude, so the other \(others.count == 1 ? "one is" : "\(others.count) are") closed first. Restore reopens \(others.count == 1 ? "it" : "them"), still signed in. (Turn on sign-in routing in Settings to skip this.)"
        alert.addButton(withTitle: "Close Others and Sign in")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await store.beginSignIn(slug)
            if let pid = await store.mainPid(slug) { Focus.show(pid: pid) }
        }
    }

    // MARK: Stack (side-by-side windows)

    enum ArrangeMode { case desktop, terminals, both }

    /// Tile the running Claude windows and/or Claude Code terminals side by side on
    /// the screen the dashboard is on.
    @MainActor private func arrange(_ mode: ArrangeMode) {
        Task {
            var targets: [ArrangeTarget] = []
            let live = sortProfiles(store.profiles)
            if mode != .terminals {
                for stat in live where stat.running {
                    if let pid = await store.mainPid(stat.effSlug) {
                        targets.append(.desktop(slug: stat.effSlug, pid: pid))
                    }
                }
            }
            if mode != .desktop {
                for stat in live where stat.remote {
                    targets.append(.terminal(slug: stat.effSlug, tty: await store.remoteTty(stat.effSlug)))
                }
            }
            guard !targets.isEmpty else {
                notice("Nothing to stack", "Open at least one Claude, or start a Remote terminal session, first.")
                return
            }
            let needsAX = targets.contains { if case .desktop = $0 { return true } else { return false } }
            if needsAX && !Arrange.isTrusted {
                Arrange.requestTrust()
                notice("Allow Accessibility to stack windows",
                       "Claude Profiles needs Accessibility access to move Claude's windows. Turn it on in System Settings, Privacy & Security, Accessibility, then choose Stack again.")
                return
            }
            let screen = NSApp.keyWindow?.screen ?? NSScreen.main
            guard let bounds = screen?.visibleFrame else { return }
            let result = Arrange.stack(targets, in: bounds)
            if !result.skipped.isEmpty {
                notice("Some windows weren't moved", result.skipped.joined(separator: "\n"))
            }
        }
    }

    @MainActor private func notice(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        a.runModal()
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
                routing: routingEnabled,
                onRoutingChange: { on in
                    if on { URLRouter.enable() } else { URLRouter.disable() }
                    routingEnabled = URLRouter.isEnabled()
                },
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
        case .remote(let slug):
            if let loaded = loadedRemote {
                RemoteSheet(
                    name: loaded.name,
                    info: loaded.info,
                    onCopy: { text in Task { await store.copy(text) } },
                    onStop: { Task { await store.remoteStop(slug); activeSheet = nil } },
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
        case .signIn: return "signin"
        }
    }

    var title: String {
        switch action {
        case .force: return "Force-quit \(name)?"
        case .restart: return "Restart \(name)?"
        case .quit: return "Quit \(name)?"
        case .signIn: return "Sign in to \(name)?"
        }
    }

    var message: String {
        switch action {
        case .force: return "Unsaved work in that Claude may be lost."
        case .restart: return "Its windows and terminals close and reopen; login and chats are kept."
        case .quit, .signIn: return ""
        }
    }

    var confirmLabel: String {
        switch action {
        case .force: return "Force Quit"
        case .restart: return "Restart"
        case .quit: return "Quit"
        case .signIn: return "Sign in"
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
