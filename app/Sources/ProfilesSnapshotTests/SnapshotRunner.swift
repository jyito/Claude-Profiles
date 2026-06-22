import SwiftUI
import AppKit
import ProfilesUI

// MARK: - Snapshot case registry

/// One golden-PNG case: a name, the view (already type-erased), and a logical
/// point size. Rendered at scale 2 with `snapshotMode` on.
@MainActor
struct SnapshotCase {
    let name: String
    let size: CGSize
    let view: AnyView
    let tolerance: Double

    // Default 1% per-pixel tolerance: absorbs cross-runner antialiasing drift —
    // goldens are recorded + visually QA'd on the maintainer's Mac, while CI runs a
    // different macOS image (the testing strategy's documented risk #1). Real
    // layout/colour regressions are many %; subtle ones are caught by the
    // maintainer's visual QA, which is the authoritative fidelity gate.
    init<V: View>(_ name: String, size: CGSize, tolerance: Double = 0.01, @ViewBuilder view: () -> V) {
        self.name = name
        self.size = size
        self.tolerance = tolerance
        // Pin the frame + opaque canvas background here so every case renders on
        // the same surface and at a deterministic size. snapshotMode is injected
        // by the renderer so animated subviews freeze.
        self.view = AnyView(
            view()
                .frame(width: size.width, height: size.height)
                .background(Theme.canvas)
        )
    }
}

// MARK: - Rendering

@MainActor
func renderPNGData<V: View>(_ view: V, scale: CGFloat = 2) -> Data? {
    let renderer = ImageRenderer(content: view.environment(\.snapshotMode, true))
    renderer.scale = scale
    renderer.isOpaque = true
    guard let cg = renderer.cgImage else { return nil }
    let rep = NSBitmapImageRep(cgImage: cg)
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Paths

private let repoRoot: URL = {
    // The runner's cwd under `swift run` is the package dir (app/). The repo
    // root is its parent. Golden PNGs live in app/Tests/__Snapshots__.
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()

private let snapshotsDir = repoRoot.appendingPathComponent("Tests/__Snapshots__", isDirectory: true)
private let pngdiffPy = repoRoot.appendingPathComponent("../tests/snapshot/pngdiff.py").standardizedFileURL

private func goldenURL(_ name: String) -> URL {
    snapshotsDir.appendingPathComponent("\(name)@2x.png")
}

// MARK: - Diff via pngdiff.py

private func python3Available() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["python3", "--version"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 }
    catch { return false }
}

/// Returns (passed, message). If python3 is unavailable, a byte-equality fallback
/// keeps the suite meaningful without spuriously failing on a bad host.
private func diff(golden: URL, actual: URL, tolerance: Double) -> (Bool, String) {
    if python3Available() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", pngdiffPy.path, golden.path, actual.path, String(tolerance)]
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = outPipe
        do {
            try p.run()
            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            p.waitUntilExit()
            return (p.terminationStatus == 0, out.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (false, "pngdiff launch failed: \(error)")
        }
    }
    // Fallback: exact byte match.
    guard let g = try? Data(contentsOf: golden), let a = try? Data(contentsOf: actual) else {
        return (false, "missing png for byte-compare")
    }
    return (g == a, g == a ? "byte-equal (no python3)" : "byte-mismatch (no python3)")
}

// MARK: - Harness

@main
struct ProfilesSnapshotTestsMain {
    @MainActor static func main() {
        let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
        try? FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

        let cases = SnapshotCases.all()
        var failed = 0

        for c in cases {
            guard let png = renderPNGData(c.view) else {
                failed += 1
                print("Test Case 'Snapshot.\(c.name)' FAILED. ImageRenderer.cgImage was nil")
                continue
            }
            let golden = goldenURL(c.name)
            if record {
                do {
                    try png.write(to: golden)
                    print("Test Case 'Snapshot.\(c.name)' recorded.")
                } catch {
                    failed += 1
                    print("Test Case 'Snapshot.\(c.name)' FAILED. write error: \(error)")
                }
                continue
            }
            // Compare mode: write actual to a temp file, diff against golden.
            guard FileManager.default.fileExists(atPath: golden.path) else {
                failed += 1
                print("Test Case 'Snapshot.\(c.name)' FAILED. missing golden (run SNAPSHOT_RECORD=1)")
                continue
            }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(c.name).png")
            do { try png.write(to: tmp) } catch {
                failed += 1
                print("Test Case 'Snapshot.\(c.name)' FAILED. temp write error: \(error)")
                continue
            }
            let (ok, msg) = diff(golden: golden, actual: tmp, tolerance: c.tolerance)
            if ok {
                print("Test Case 'Snapshot.\(c.name)' passed. \(msg)")
            } else {
                failed += 1
                print("Test Case 'Snapshot.\(c.name)' FAILED. \(msg)")
            }
        }

        print("Executed \(cases.count) tests, with \(failed) failures")
        exit(failed == 0 ? 0 : 1)
    }
}
