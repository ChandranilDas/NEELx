cask "neelx" do
  version "2.0.0-beta.12"
  sha256 :no_check

  url "https://github.com/ChandranilDas/NEELx/releases/download/v#{version}/NEELx-v#{version}-universal.dmg"
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

    # If the user already has Xcode/CLT + their own free local Apple Development certificate,
    # re-sign NEELx.app locally so macOS preserves Accessibility & Keychain across future upgrades.
    has_tools = File.executable?("/Applications/Xcode.app/Contents/Developer/usr/bin/codesign_allocate") ||
                File.executable?("/Library/Developer/CommandLineTools/usr/bin/codesign_allocate")
    if has_tools
      identities = `/usr/bin/security find-identity -v -p codesigning 2>/dev/null`
      match = identities.match(/\)\s+([0-9A-F]{40})\s+"(?:Developer ID Application|Apple Development):/)
      if match
        entitlements = "/tmp/neelx-cask-entitlements.plist"
        File.write(entitlements, <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0"><dict><key>com.apple.security.device.camera</key><true/></dict></plist>
        XML
        system_command "/usr/bin/codesign",
                       args: ["--force", "--sign", match[1], "--entitlements", entitlements, "#{appdir}/NEELx.app"],
                       sudo: false
        File.delete(entitlements) if File.exist?(entitlements)
      end
    end
  end

  zap trash: [
    "~/Library/Application Support/NEELx",
    "~/Library/Preferences/local.neelx.plist",
  ]
end
