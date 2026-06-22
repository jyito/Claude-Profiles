import SwiftUI
import ProfilesCore

@main
struct ProfilesApp: App {
    var body: some Scene {
        WindowGroup("Claude Profiles") {
            Text("Claude Profiles \(ProfilesCore.version)")
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
