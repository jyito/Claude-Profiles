# Postmortem — Claude Desktop leaks `/dev/ptmx` master fds (system-wide pty exhaustion)

- **Date:** 2026-06-21
- **Author:** jyito (with Claude)
- **Status:** Root cause confirmed (high confidence). Mitigation shipped in this
  project (v0.6.0); the real fix is upstream and belongs to Anthropic.
- **Severity:** High — at the limit, *every* terminal on the Mac fails
  (`forkpty: Device not configured`) until the leaking app is quit.

## Summary

Claude Desktop's Electron **main** process accumulates orphaned `/dev/ptmx`
**master** file descriptors over its lifetime. Each pseudo-terminal it spawns
(for Claude Code sessions, a login `/bin/zsh -l`, bash) leaks one master fd that
is never `close()`d. They pile up until the system pty pool
(`kern.tty.ptmx_max`, **511** on macOS) is exhausted, after which
`posix_openpt()` fails **system-wide** — terminals everywhere die with
`forkpty: Device not configured` — until Claude Desktop is quit.

**Root cause:** Claude Desktop bundles Microsoft **`node-pty 1.1.0-beta34`**,
which has a known macOS `/dev/ptmx` master-fd leak. It was fixed upstream in
[node-pty PR #882](https://github.com/microsoft/node-pty/pull/882)
("fix: /dev/ptmx leak on macOS"), released in **v1.2.0-beta.10**. `1.1.0-beta34`
predates that fix, so Claude ships the **unpatched** code. The defect is inside
node-pty's native spawn path — *not* in Claude's wrapper — so it cannot be
worked around by better caller-side cleanup (`kill()`/`onExit`/`dispose()`).

This is **not a bug in Claude Profiles.** Claude Profiles only *detects* the leak
and offers the one remediation available from outside the leaking process.

## Evidence

Gathered read-only with `lsof`/`ps` on a running Claude Desktop:

- **The masters live on the Electron _main_ process** (`Claude.app/Contents/MacOS/Claude`,
  ppid 1, no `--user-data-dir`) — never the GPU/renderer/utility helpers, and never
  the bundled Claude Code agents (those are wired over unix-domain socketpairs, not ptys).
- **Orphan signature, reproduced on two instances.** Cross-referencing each master's
  device minor `(15,N)` against every slave minor `(16,N)` system-wide: on one instance
  **53 masters, exactly 1 paired with a live slave (the active session), 52 orphaned**;
  a second instance independently showed **25 masters, 1 paired, 24 orphaned**. The one
  paired master proves node-pty pairs correctly while a session is live; the orphan pile
  proves the master is never released afterward. Earlier peak observed: **494 of 511**
  across two instances. Distinct fd numbers and distinct device minors rule out any
  measurement/dedup artifact.
- **The mechanism is node-pty.** The bundle ships
  `Contents/Resources/app.asar.unpacked/node_modules/node-pty/build/Release/pty.node`,
  `package.json` version **`1.1.0-beta34`**. node-pty's `forkpty`/`posix_openpt` is
  exactly what allocates a `/dev/ptmx` master.
- **Caller does not (and cannot) save it.** On natural exit the app drops its bookkeeping
  but never `destroy()`/`kill()`s the pty; the only kill path is signal-only and closes no
  fd. node-pty owns the master internally — there is no documented caller API to close it.

## Why restart is the only external fix

A file-descriptor table is **private to the process that owns it**. There is no
syscall to `close()` another process's fd — by design. The kernel reclaims a
process's entire fd table only when the process **exits**. So the only external
action that frees the orphaned masters is making the holder (the Claude Desktop
main process) exit and respawn.

That is precisely what Claude Profiles' per-instance **Restart** does
(`engine.sh restart <slug>`: TERM the tree → wait → `kill -9` if needed →
relaunch), with an opt-in auto-restart over a threshold. Because the leak is
inside node-pty, *no* amount of cleanup in Claude Profiles (or any external tool)
could release the masters short of restarting the process — restart isn't a lazy
fallback, it's the only lever that exists.

## Confidence & open questions

**High** that the leak is real, Claude-Desktop-main-owned, node-pty-driven, tied
to interactive pty spawns, and reclaimable only by the holder exiting — two
instances reproduce a clean signature, every alternative was tested and ruled out
with read-only `lsof`/`ps`, and the upstream fixing PR plus two sibling-tool
issues corroborate.

**Not pinned down** (and we say so rather than overclaim): the *exact* leak site
was inferred, not traced. Two candidate mechanisms point to the same outcome —
(a) PR #882's off-by-one in native `pty_posix_spawn()` cleanup leaks the master
**at spawn time**; (b) a macOS `ReadStream` 'close'/`EIO` event that node-pty's
own code notes "sometimes never gets closed." Distinguishing them would require
`dtrace` on `posix_openpt`/`close` across a spawn+exit cycle (needs sudo) or
decompiling the asar JS. Neither caveat changes the verdict or the fix.

## Upstream status

Already reported to Anthropic (and a known node-pty class of bug):

- [anthropics/claude-code #65995](https://github.com/anthropics/claude-code/issues/65995)
  — same symptom (Electron main, ~509/511, restart-only); labeled a duplicate.
- [google-gemini/gemini-cli #15945](https://github.com/google-gemini/gemini-cli/issues/15945)
  — identical leak in a sibling tool also on node-pty 1.1.0.
- node-pty: [PR #882](https://github.com/microsoft/node-pty/pull/882) (the fix,
  in v1.2.0-beta.10); related [#710](https://github.com/microsoft/node-pty/issues/710),
  [#657](https://github.com/microsoft/node-pty/issues/657).
  (node-pty #375, referenced inside Claude's asar, is an *unrelated* Windows
  ConPTY issue — a red herring.)

**The real fix is Anthropic's:** bump the bundled `node-pty` to **≥ 1.2.0-beta.10**
(or backport PR #882). Until then, restarting the affected instance is the only
remedy available to anyone outside Anthropic.

## Mitigation in this repo

- `src/engine.sh`: `ptmx_count_for_pids` / `ptmx_max` (stats fields `ptmx`,
  `ptmxMax`), `remote_live`, and `restart <slug>` (the reclaim).
- `src/dashboard.html`: the per-card **"N leaked"** stat (brightens past the
  threshold), the **Restart to free handles** action in **+ Details**, and the
  system-wide banner near the ceiling.
- Opt-in **auto-restart** over a threshold (`autoRestartLeakAt`, enforced in
  `autotick`).
