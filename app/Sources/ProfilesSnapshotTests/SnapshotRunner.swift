import SwiftUI
import AppKit

@MainActor
func renderPNG<V: View>(_ view: V, scale: CGFloat = 2) -> NSBitmapImageRep? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    renderer.isOpaque = true
    guard let cg = renderer.cgImage else { return nil }
    return NSBitmapImageRep(cgImage: cg)
}

struct ProbeView: View {
    var body: some View {
        Text("snap")
            .font(.system(size: 20, weight: .medium))
            .frame(width: 120, height: 60)
            .background(Color(red: 0.12, green: 0.118, blue: 0.094))
    }
}

@main
struct ProfilesSnapshotTestsMain {
    @MainActor static func main() {
        var failed = 0
        if let rep = renderPNG(ProbeView(), scale: 2) {
            // 120×60 @2x → 240×120 device pixels
            if rep.pixelsWide == 240 && rep.pixelsHigh == 120 && (rep.representation(using: .png, properties: [:])?.count ?? 0) > 0 {
                print("Test Case 'SnapshotProbe.rendersHeadless' passed.")
            } else {
                failed += 1
                print("Test Case 'SnapshotProbe.rendersHeadless' FAILED. got \(rep.pixelsWide)x\(rep.pixelsHigh)")
            }
        } else {
            failed += 1
            print("Test Case 'SnapshotProbe.rendersHeadless' FAILED. ImageRenderer.cgImage was nil")
        }
        print("Executed 1 tests, with \(failed) failures")
        exit(failed == 0 ? 0 : 1)
    }
}
