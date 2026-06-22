import SwiftUI
import AppKit

/// Sidebar vibrancy: an `NSVisualEffectView` behind the window. Materials are
/// used only on the sidebar + sheets, never on resting data cards. Snapshot
/// content never includes this (live vibrancy is non-deterministic).
public struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    public init(material: NSVisualEffectView.Material = .underWindowBackground,
                blending: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blending = blending
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
        nsView.state = .active
    }
}
