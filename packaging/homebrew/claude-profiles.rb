# Homebrew cask for Claude Profiles (signed + notarized releases).
#
# To publish: copy this file into a tap repo's Casks/ directory
# (github.com/jyito/homebrew-tap → Casks/claude-profiles.rb), then users install with
#   brew install --cask jyito/tap/claude-profiles
#
# Per release, bump `version` to the tag and set `sha256` to the DMG hash from the
# release's SHA256SUMS.txt (or `shasum -a 256 Claude-Profiles.dmg`).

cask "claude-profiles" do
  version "0.6.1"
  sha256 "888d7892ca7559d0506ed83c75cc1fc332b7203eabc0f4e25f1184af1e21bae4"

  url "https://github.com/jyito/Claude-Profiles/releases/download/v#{version}/Claude-Profiles.dmg",
      verified: "github.com/jyito/Claude-Profiles/"
  name "Claude Profiles"
  desc "Run multiple Claude Desktop accounts side by side"
  homepage "https://github.com/jyito/Claude-Profiles"

  # The dashboard + one-click Show Window rely on macOS 14+ behaviour.
  depends_on macos: :sonoma

  app "Claude Profiles.app"

  # `brew uninstall` removes only the app. `brew uninstall --zap` ALSO deletes the
  # data below — which includes each profile's SAVED LOGIN. Listed for completeness;
  # zap is an explicit, deliberate "erase everything" action.
  zap trash: [
    "~/.claude-code-instances",   # per-profile Claude Code sessions/config
    "~/.claude-instances",        # profile data dirs (saved logins!) + runtime applet
  ]
end
