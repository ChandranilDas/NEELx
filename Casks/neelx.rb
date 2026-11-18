cask "neelx" do
  version "2.0.0-beta.3"
  sha256 "2fb5d0a5a0884e6d5665849ce2e001bd63c2158760cfecc9261f2a01551e30cd"

  url "https://github.com/ChandranilDas/NEELx/releases/download/v#{version}/NEELx-v#{version}-universal-lite.dmg"
  name "NEELx"
  desc "Hardened offline biometric Face Unlock for macOS with Stage 3 Neural 3D Depth"
  homepage "https://chandranildas.github.io/NEELx/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"

  app "NEELx.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/NEELx.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/NEELx",
    "~/Library/Preferences/local.neelx.plist",
  ]
end
