import Foundation
import ProfilesCore

/// Deterministic fixtures for golden-PNG snapshots. No `Date.now`, no randomness —
/// every value is frozen so `ImageRenderer` output is reproducible.
enum Fixtures {
    // A calm, running profile (blue badge).
    static let business = ProfileStat(
        name: "Business", slug: "business", running: true,
        cpu: 42.0, mem: 2230, procs: 7, ptys: 3,
        ptmx: 40, ptmxMax: 512, disk: 1840, opens: 23,
        last: "2026-06-20", color: "#3B7DD8", remote: true
    )

    // An actively-leaking, running profile (purple badge): it holds far more ptmx
    // masters (held handles) than it has live terminals (5) — the leak signature. The
    // absolute level is well under any ceiling, the whole point of the amber-only
    // rework: a real leak shows amber regardless of how far the system pool is from
    // exhaustion. Drives the amber `.leaking` card / detail / leak-block goldens.
    static let research = ProfileStat(
        name: "Research", slug: "research", running: true,
        cpu: 118.0, mem: 5400, procs: 11, ptys: 5,
        ptmx: 96, ptmxMax: 512, disk: 3120, opens: 58,
        last: "2026-06-21", color: "#7C5CC4", remote: false
    )

    // A stopped profile (pink badge).
    static let clientX = ProfileStat(
        name: "Client X", slug: "clientx", running: false,
        cpu: 0, mem: 0, procs: 0, ptys: 0,
        ptmx: 0, ptmxMax: 512, disk: 920, opens: 12,
        last: "2026-06-18", color: "#D25F8C", remote: false
    )

    // The default (system) instance — empty slug, disk sentinel -1.
    static let defaultInstance = ProfileStat(
        name: "Claude (default)", slug: "", running: true,
        cpu: 18.0, mem: 1180, procs: 5, ptys: 2,
        ptmx: 22, ptmxMax: 512, disk: -1, opens: 0,
        last: "", color: "#6E6A62", remote: false
    )

    // The default (system) instance while it is itself leaking handles. Same protected
    // contract as `defaultInstance` (no CTA), but its informational leak line reads
    // amber "⚠ N leaked". Drives the `card-default-leaking` golden — the maintainer's
    // original concern (the default card previously showed NO leak readout at all).
    static let defaultLeaking = ProfileStat(
        name: "Claude (default)", slug: "", running: true,
        cpu: 18.0, mem: 1180, procs: 5, ptys: 2,
        ptmx: 58, ptmxMax: 512, disk: -1, opens: 0,
        last: "", color: "#6E6A62", remote: false
    )

    // The default (system) instance after the user quits it: empty slug (→ default),
    // `running:false`, zeroed metrics. Drives the `card-default-stopped` golden — the
    // relaunch affordance (Open → opendefault) that the bug used to suppress.
    static let defaultStopped = ProfileStat(
        name: "Claude (default)", slug: "", running: false,
        cpu: 0, mem: 0, procs: 0, ptys: 0,
        ptmx: 0, ptmxMax: 512, disk: -1, opens: 0,
        last: "", color: "#6E6A62", remote: false
    )

    static let all: [ProfileStat] = [defaultInstance, business, research, clientX]

    // Three terminals for the inspector drill-down: an active pty host, an idle
    // shell, and one with unknown idle (the -1 sentinel → "—").
    static let terminals: [TerminalInfo] = [
        TerminalInfo(dev: "/dev/ttys003", pid: 4821, cmd: "node --max-old-space-size=4096 /opt/claude/pty-host.js", idle: 12),
        TerminalInfo(dev: "/dev/ttys007", pid: 4990, cmd: "-zsh", idle: 540),
        TerminalInfo(dev: "/dev/ttys011", pid: 5102, cmd: "claude --resume", idle: -1),
    ]

    // Fixed 30-point series. Hand-built so the curve reads clearly in a PNG.
    static let cpuSeries: [Double] = [
        12, 18, 22, 19, 25, 31, 28, 35, 40, 38,
        44, 52, 48, 55, 61, 58, 64, 60, 57, 62,
        70, 66, 59, 53, 49, 45, 50, 47, 43, 42,
    ]

    static let memSeries: [Double] = [
        1800, 1820, 1850, 1880, 1860, 1900, 1950, 1980, 2010, 2040,
        2020, 2060, 2100, 2080, 2120, 2150, 2180, 2160, 2200, 2230,
        2210, 2240, 2260, 2240, 2230, 2250, 2270, 2250, 2240, 2230,
    ]

    // Research's hotter CPU history (per-core > 100%).
    static let cpuSeriesHot: [Double] = [
        60, 72, 80, 95, 110, 102, 118, 125, 120, 130,
        128, 135, 122, 140, 138, 145, 132, 150, 142, 138,
        130, 125, 120, 128, 122, 118, 115, 120, 118, 118,
    ]

    static let memSeriesHot: [Double] = [
        4200, 4400, 4600, 4800, 5000, 5100, 5300, 5200, 5400, 5500,
        5300, 5600, 5800, 5700, 5900, 5400, 5600, 5800, 5500, 5400,
        5200, 5400, 5600, 5300, 5400, 5500, 5300, 5400, 5400, 5400,
    ]

    // Research's leaked-handle (ptmx) history climbing steadily — ends at 96 (matching
    // `research.ptmx`), far below the 512 ceiling. The rising slope under a flat
    // ceiling rule is the leak tell; the amber verdict no longer waits for the pool to
    // approach exhaustion.
    static let ptmxSeriesHot: [Double] = [
        18, 22, 26, 30, 33, 38, 42, 45, 49, 52,
        55, 58, 60, 63, 66, 68, 71, 74, 77, 79,
        82, 84, 86, 88, 90, 91, 92, 94, 95, 96,
    ]
}
