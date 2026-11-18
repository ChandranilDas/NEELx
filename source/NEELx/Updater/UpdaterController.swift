//
//  UpdaterController.swift
//  NEELx
//
//  Native zero-dependency GitHub Releases auto-updater pointing exclusively at
//  `NEELxConfig.githubRepository` (`ChandranilDas/NEELx`). Checks daily in the
//  background and on demand, displays release notes, and performs 1-click DMG
//  download + mount + atomic `/Applications/NEELx.app` swap & relaunch (falling back
//  cleanly to Finder if `/Applications` isn't writable). Preserves enrolled faces & Keychain.
//

import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class UpdaterController {
    private static let autoCheckKey = "NEELxUpdater.automaticallyChecks"
    private static let lastCheckKey = "NEELxUpdater.lastCheckTimestamp"

    var automaticallyChecksForUpdates: Bool {
        didSet { UserDefaults.standard.set(automaticallyChecksForUpdates, forKey: Self.autoCheckKey) }
    }

    private(set) var canCheckForUpdates: Bool = true
    private(set) var isPresentingUpdateUI: Bool = false
    private(set) var statusText: String? = nil

    private var timer: Timer?
    private var activeTask: Task<Void, Never>?

    init() {
        automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true
    }

    func start() {
        // Check silently shortly after launch if >= 24h since last check
        if automaticallyChecksForUpdates {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await self?.checkIfDue()
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkIfDue()
            }
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.performCheck(userInitiated: true)
        }
    }

    private func checkIfDue() async {
        guard automaticallyChecksForUpdates, canCheckForUpdates else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        let now = Date().timeIntervalSince1970
        guard now - last >= 24 * 60 * 60 else { return }
        await performCheck(userInitiated: false)
    }

    // MARK: - GitHub Releases API

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: String
        let draft: Bool
        let prerelease: Bool
        let assets: [GitHubAsset]
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int
    }

    private func performCheck(userInitiated: Bool) async {
        canCheckForUpdates = false
        if userInitiated { statusText = "Checking for updates…" }
        defer { canCheckForUpdates = true }

        guard let url = URL(string: "https://api.github.com/repos/\(NEELxConfig.githubRepository)/releases?per_page=10") else {
            if userInitiated { statusText = "Invalid update repository configuration." }
            return
        }

        do {
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("NEELx-Updater/2.0", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                if userInitiated { statusText = "Couldn't reach GitHub Releases right now." }
                return
            }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                .filter { !$0.draft }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
            guard let newest = releases.first(where: { Self.isVersion($0.tag_name, newerThan: currentVersion) }) else {
                if userInitiated {
                    statusText = "You're up to date (v\(currentVersion))."
                    presentUpToDateAlert(currentVersion: currentVersion)
                }
                return
            }

            statusText = "Update available: \(newest.tag_name)"
            presentUpdateAlert(release: newest, currentVersion: currentVersion)
        } catch {
            if userInitiated {
                statusText = "Update check failed: \(error.localizedDescription)"
            }
        }
    }

    private func presentUpToDateAlert(currentVersion: String) {
        isPresentingUpdateUI = true
        defer { isPresentingUpdateUI = false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "NEELx is Up to Date"
        alert.informativeText = "NEELx \(currentVersion) is currently the newest version available on GitHub."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentUpdateAlert(release: GitHubRelease, currentVersion: String) {
        isPresentingUpdateUI = true
        NSApp.activate(ignoringOtherApps: true)

        let preferredAsset = selectBestDMG(from: release.assets)
        let sizeNote = preferredAsset.map { String(format: " (%.1f MB)", Double($0.size) / (1024 * 1024)) } ?? ""
        let notesPreview = (release.body ?? "")
            .components(separatedBy: "\n")
            .prefix(10)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "New NEELx Update Available: \(release.tag_name)"
        alert.informativeText = """
        You're running v\(currentVersion). \(release.name ?? release.tag_name) is ready to install\(sizeNote).

        \(notesPreview.isEmpty ? "Includes performance, lighting, and security improvements." : notesPreview)
        """

        if preferredAsset != nil {
            alert.addButton(withTitle: "Install & Relaunch")
        }
        alert.addButton(withTitle: "View on GitHub")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        isPresentingUpdateUI = false

        if let asset = preferredAsset, response == .alertFirstButtonReturn {
            activeTask = Task { [weak self] in
                await self?.downloadAndInstall(asset: asset, releaseURL: release.html_url)
            }
        } else if (preferredAsset == nil && response == .alertFirstButtonReturn) ||
                  (preferredAsset != nil && response == .alertSecondButtonReturn) {
            if let url = URL(string: release.html_url) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Matches the user's current install flavor: Lite if depth model isn't bundled inside `Bundle.main`, else Full.
    private func selectBestDMG(from assets: [GitHubAsset]) -> GitHubAsset? {
        let dmgs = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        guard !dmgs.isEmpty else { return nil }

        let hasBundledDepth = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc") != nil
        if !hasBundledDepth, let lite = dmgs.first(where: { $0.name.lowercased().contains("lite") }) {
            return lite
        }
        if let full = dmgs.first(where: { !$0.name.lowercased().contains("lite") && $0.name.lowercased().contains("universal") }) {
            return full
        }
        return dmgs.first
    }

    // MARK: - Download, Mount & Atomic Self-Install

    private func downloadAndInstall(asset: GitHubAsset, releaseURL: String) async {
        canCheckForUpdates = false
        statusText = "Downloading \(asset.name)…"
        defer { canCheckForUpdates = true }

        guard let downloadURL = URL(string: asset.browser_download_url) else { return }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("NEELx-Update-\(UUID().uuidString)", isDirectory: true)
        let dmgURL = tempDir.appendingPathComponent(asset.name)
        let mountDir = tempDir.appendingPathComponent("mount", isDirectory: true)

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let expectedFallback = Double(max(asset.size, 1))
            let downloader = FastFileDownloader()
            let downloadedTemp = try await downloader.download(from: downloadURL, userAgent: "NEELx-Updater/2.0") { [weak self] written, expected in
                let denom = expected > 0 ? Double(expected) : expectedFallback
                let pct = Int(min(Double(written) * 100.0 / denom, 99.0))
                Task { @MainActor [weak self] in
                    self?.statusText = "Downloading update… \(pct)%"
                }
            }
            if fm.fileExists(atPath: dmgURL.path) {
                try fm.removeItem(at: dmgURL)
            }
            try fm.moveItem(at: downloadedTemp, to: dmgURL)

            statusText = "Installing update…"
            try fm.createDirectory(at: mountDir, withIntermediateDirectories: true)

            // Mount DMG silently, verify NEELx.app inside, copy to /Applications/NEELx.app, unmount, relaunch
            let installed = await Task.detached(priority: .userInitiated) { () -> Bool in
                let attach = Process()
                attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                attach.arguments = ["attach", dmgURL.path, "-mountpoint", mountDir.path, "-nobrowse", "-quiet"]
                try? attach.run()
                attach.waitUntilExit()
                guard attach.terminationStatus == 0 else { return false }

                defer {
                    let detach = Process()
                    detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                    detach.arguments = ["detach", mountDir.path, "-quiet", "-force"]
                    try? detach.run()
                    detach.waitUntilExit()
                }

                let newApp = mountDir.appendingPathComponent("NEELx.app")
                guard FileManager.default.fileExists(atPath: newApp.path) else { return false }

                // Replace currently running bundle (defaulting to /Applications/NEELx.app)
                let currentApp = Bundle.main.bundleURL.path.hasSuffix(".app")
                    ? Bundle.main.bundleURL
                    : URL(fileURLWithPath: "/Applications/NEELx.app")
                let parentDir = currentApp.deletingLastPathComponent()
                guard FileManager.default.isWritableFile(atPath: parentDir.path) else { return false }

                let backupApp = parentDir.appendingPathComponent(".NEELx-old-\(UUID().uuidString).app")
                let stagingApp = parentDir.appendingPathComponent(".NEELx-new-\(UUID().uuidString).app")

                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["--norsrc", newApp.path, stagingApp.path]
                try? ditto.run()
                ditto.waitUntilExit()
                guard ditto.terminationStatus == 0 else {
                    try? FileManager.default.removeItem(at: stagingApp)
                    return false
                }

                // If this Mac has its own free local `Apple Development:` (or `Developer ID Application:`)
                // certificate installed, re-sign the updated bundle locally with that stable identity so
                // macOS preserves Accessibility & Keychain permissions silently across auto-updates.
                Self.reSignWithLocalUserCertIfAvailable(appURL: stagingApp)

                do {
                    if FileManager.default.fileExists(atPath: currentApp.path) {
                        try FileManager.default.moveItem(at: currentApp, to: backupApp)
                    }
                    try FileManager.default.moveItem(at: stagingApp, to: currentApp)
                    try? FileManager.default.removeItem(at: backupApp)
                    return true
                } catch {
                    // Roll back safely on any error
                    if FileManager.default.fileExists(atPath: backupApp.path),
                       !FileManager.default.fileExists(atPath: currentApp.path) {
                        try? FileManager.default.moveItem(at: backupApp, to: currentApp)
                    }
                    try? FileManager.default.removeItem(at: stagingApp)
                    return false
                }
            }.value

            if installed {
                statusText = "Update installed — relaunching NEELx…"
                let appPath = Bundle.main.bundleURL.path.hasSuffix(".app")
                    ? Bundle.main.bundleURL.path
                    : "/Applications/NEELx.app"
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c", "sleep 0.6 && open -n \"\(appPath)\""]
                try? relaunch.run()
                try? fm.removeItem(at: tempDir)
                NSApplication.shared.terminate(nil)
            } else {
                // Graceful fallback: save DMG into ~/Downloads and open it in Finder
                let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
                let savedDMG = downloads.appendingPathComponent(asset.name)
                try? fm.removeItem(at: savedDMG)
                try? fm.copyItem(at: dmgURL, to: savedDMG)
                try? fm.removeItem(at: tempDir)
                statusText = "Downloaded to Downloads — drag NEELx.app into Applications."
                NSWorkspace.shared.open(savedDMG)
            }
        } catch {
            try? fm.removeItem(at: tempDir)
            statusText = "Update download failed: \(error.localizedDescription)"
            if let url = URL(string: releaseURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Re-signs `appURL` using the user's own local `Developer ID Application:` or `Apple Development:`
    /// certificate if Xcode/CLT is already installed. Strictly checks for `codesign_allocate` first so
    /// non-developer Macs never see an "Install Command Line Tools" popup.
    private nonisolated static func reSignWithLocalUserCertIfAvailable(appURL: URL) {
        let fm = FileManager.default
        let hasCodesignTools = fm.isExecutableFile(atPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/codesign_allocate")
            || fm.isExecutableFile(atPath: "/Library/Developer/CommandLineTools/usr/bin/codesign_allocate")
        guard hasCodesignTools else { return }

        let sec = Process()
        sec.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        sec.arguments = ["find-identity", "-v", "-p", "codesigning"]
        let pipe = Pipe()
        sec.standardOutput = pipe
        sec.standardError = Pipe()
        guard (try? sec.run()) != nil else { return }
        sec.waitUntilExit()
        guard sec.terminationStatus == 0 else { return }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = output.components(separatedBy: .newlines)

        func firstIdentityHash(matching needle: String) -> String? {
            for line in lines where line.contains(needle) {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2, parts[1].count == 40 {
                    return parts[1]
                }
            }
            return nil
        }

        guard let identity = firstIdentityHash(matching: "Developer ID Application:")
            ?? firstIdentityHash(matching: "Apple Development:") else {
            return
        }

        let entitlementsURL = fm.temporaryDirectory.appendingPathComponent("neelx-entitlements-\(UUID().uuidString).plist")
        let entitlementsXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.security.device.camera</key>
            <true/>
        </dict>
        </plist>
        """
        defer { try? fm.removeItem(at: entitlementsURL) }
        guard (try? entitlementsXML.write(to: entitlementsURL, atomically: true, encoding: .utf8)) != nil else { return }

        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-cr", appURL.path]
        try? xattr.run()
        xattr.waitUntilExit()

        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", identity, "--entitlements", entitlementsURL.path, appURL.path]
        sign.standardOutput = Pipe()
        sign.standardError = Pipe()
        try? sign.run()
        sign.waitUntilExit()
    }

    // MARK: - SemVer Comparison (`2.0.0-beta.1` < `2.0.0-beta.2` < `2.0.0` < `2.0.1`)

    nonisolated static func isVersion(_ remoteRaw: String, newerThan localRaw: String) -> Bool {
        let r = parseVersion(remoteRaw)
        let l = parseVersion(localRaw)
        for i in 0..<3 {
            if r.core[i] != l.core[i] { return r.core[i] > l.core[i] }
        }
        // Stable release beats pre-release of the same core version (e.g., 2.0.0 > 2.0.0-beta.2)
        if r.prerelease.isEmpty && !l.prerelease.isEmpty { return true }
        if !r.prerelease.isEmpty && l.prerelease.isEmpty { return false }
        if r.prerelease == l.prerelease { return false }
        return r.prerelease.compare(l.prerelease, options: .numeric) == .orderedDescending
    }

    private nonisolated static func parseVersion(_ raw: String) -> (core: [Int], prerelease: String) {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^v", with: "", options: .regularExpression)
        let parts = cleaned.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let nums = parts[0].split(separator: ".").compactMap { Int($0) }
        let core = [
            nums.indices.contains(0) ? nums[0] : 0,
            nums.indices.contains(1) ? nums[1] : 0,
            nums.indices.contains(2) ? nums[2] : 0,
        ]
        let pre = parts.count > 1 ? String(parts[1]) : ""
        return (core, pre)
    }
}
