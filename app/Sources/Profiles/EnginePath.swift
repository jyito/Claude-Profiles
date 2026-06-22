import Foundation

/// Resolve the path to `engine.sh`. Dev uses the `SPIKE_ENGINE` env var pointing
/// at the repo `src/engine.sh`; the bundled copy (Phase 6) is the fallback.
func resolveEnginePath() -> String {
    if let env = ProcessInfo.processInfo.environment["SPIKE_ENGINE"], !env.isEmpty {
        return env
    }
    if let res = Bundle.main.resourcePath {
        let bundled = res + "/engine.sh"
        if FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
    }
    return "engine.sh"
}
