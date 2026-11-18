cask "neelx" do
  version "2.0.0-beta.3"
  sha256 "35809af8ee3f0de5bc2224711e6eb92537602a1295f92dfecb9e6e0133261de3"

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
