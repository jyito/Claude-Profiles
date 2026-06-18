# Homebrew cask — DRAFT TEMPLATE (not yet publishable).
#
# Blocked on signing + notarization: Homebrew and macOS reject an unsigned cask
# app for downloaders. Once releases are signed + notarized (see docs/SIGNING.md),
# per release: set `version` to the tag and `sha256` to `shasum -a 256` of the DMG,
# then copy this file into a tap repo's Casks/ directory
# (e.g. github.com/jyito/homebrew-tap → Casks/claude-profiles.rb).
#
# Users would then install with:
#   brew install --cask jyito/tap/claude-profiles

cask "claude-profiles" do
  version "0.5.1"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # TODO: shasum -a 256 of the release DMG

  url "https://github.com/jyito/Claude-Profiles/releases/download/v#{version}/Claude-Profiles.dmg",
      verified: "github.com/jyito/Claude-Profiles/"
  name "Claude Profiles"
  desc "Run multiple Claude Desktop accounts side by side on one Mac"
  homepage "https://github.com/jyito/Claude-Profiles"

  # The dashboard + one-click Show Window rely on macOS 14+ behaviour.
  depends_on macos: ">= :sonoma"

  app "Claude Profiles.app"

  # `brew uninstall` removes only the app. `brew uninstall --zap` ALSO deletes the
  # data below — which includes each profile's SAVED LOGIN. Listed for completeness;
  # zap is an explicit, deliberate "erase everything" action.
  zap trash: [
    "~/.claude-instances",        # profile data dirs (saved logins!) + runtime applet
    "~/.claude-code-instances",   # per-profile Claude Code sessions/config
  ]
end
