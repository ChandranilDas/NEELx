//
//  NEELxConfig.swift
//  NEELx
//
//  Central open-source & beta distribution configuration.
//  Update these constants before publishing your GitHub repository or beta DMG.
//

import Foundation

enum NEELxConfig {
    /// Your GitHub repository slug (`owner/repo`) used for pre-filled bug reports & feature requests.
    static let githubRepository = "ChandranilDas/NEELx"

    /// Direct email address for testers without a GitHub account.
    static let feedbackEmail = "chandranildas925@gmail.com"

    /// Optional HTTPS webhook URL (e.g., Formspree `https://formspree.io/f/xxxxxx`, Discord webhook, or custom endpoint).
    /// When set, testers can submit feedback directly inside NEELx with 1 click and zero browser/GitHub account!
    static let feedbackWebhookURL = ""

    static var githubRepoURL: URL? {
        URL(string: "https://github.com/\(githubRepository)")
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "2.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "2"
        return "Version \(short) (\(build))"
    }

    /// Privacy-scrubbed Markdown environment summary (zero names, passwords, or biometric data).
    @MainActor
    static func diagnosticsMarkdown() -> String {
        let settings = NEELxSettings.shared
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let hwModel = sysctlString("hw.model") ?? "Unknown Mac"
        let cpuBrand = sysctlString("machdep.cpu.brand_string") ?? sysctlString("hw.machine") ?? "Unknown CPU"
        let activeCamera = CameraDeviceCatalog.resolvedDevice()?.localizedName ?? "None"
        let depthReady = NeuralDepthAnalyzer.shared.isModelAvailable
        return """
        ### NEELx Diagnostics
        - **App Version**: \(versionString)
        - **Mac Model**: \(hwModel) (\(cpuBrand))
        - **macOS**: \(osVersion)
        - **Active Camera**: \(activeCamera) (Clamshell: \(CameraDeviceCatalog.isClamshellMode()))
        - **3D Neural Depth (ANE)**: \(depthReady ? (settings.neuralDepthEnabled ? "Enabled (Model Ready)" : "Disabled in Settings") : "Not Installed")
        - **Match Threshold**: \(String(format: "%.2f", settings.matchThreshold))
        - **Active Chromatic Flash**: \(settings.chromaticFlashEnabled ? "On" : "Off")
        - **Adaptive Learning**: \(settings.adaptiveLearningEnabled ? "On" : "Off")
        - **Walk-Away Presence Lock**: \(settings.presenceAutoLockEnabled ? "On (\(settings.presenceAutoLockSeconds)s)" : "Off")
        """
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
