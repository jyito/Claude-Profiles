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
                            // New Profile sheet is Phase 4.
                        } label: {
                            Label("New Profile", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButtonStyle(.prominentCoral))
                        .padding(Theme.Space.md)
                        .accessibilityIdentifier("sidebar-new-profile")
                    }
            } detail: {
                DashboardView(store: store, selection: $selection, inspectorShown: $inspectorShown)
                    .navigationTitle("Profiles")
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Image(systemName: "square.on.square")
                                .foregroundStyle(Theme.coral)
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                // New Profile sheet is Phase 4.
                            } label: {
                                Label("New Profile", systemImage: "plus")
                            }
                            .accessibilityIdentifier("toolbar-new-profile")
                        }
                    }
            }
            .frame(minWidth: 840, minHeight: 560)
            .background(Theme.canvas)
            .preferredColorScheme(.dark)
            .onAppear { store.start() }
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
}
