//
//  CheckMySetupView.swift
//  NEELx
//
//  Item #6 & #7: In-app "Check My Setup" diagnostic screen.
//  Inspects Camera, Accessibility, Input Monitoring, Keychain session,
//  Core ML models (distinguishing missing vs load errors), Login Item,
//  and code signing integrity. Offers individual component repair actions.
//

import SwiftUI
import AppKit
import AVFoundation
import ServiceManagement
import Security

enum DiagnosticStatus: Equatable {
    case healthy(String)
    case warning(String)
    case failure(String)

    var iconName: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .healthy: return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .warning: return Color.orange
        case .failure: return Color.red
        }
    }

    var text: String {
        switch self {
        case .healthy(let msg), .warning(let msg), .failure(let msg):
            return msg
        }
    }

    var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }
}

struct DiagnosticRowData: Identifiable {
    let id: String
    let title: String
    let iconName: String
    let status: DiagnosticStatus
    let detail: String
    let actionTitle: String?
    let action: (() -> Void)?
}

@MainActor
@Observable
final class CheckMySetupModel {
    var rows: [DiagnosticRowData] = []
    var isChecking = false
    var lastChecked: Date?
    var didCopyReport = false

    var overallHealthy: Bool {
        rows.allSatisfy { $0.status.isHealthy }
    }

    var attentionCount: Int {
        rows.filter { !$0.status.isHealthy }.count
    }

    func runChecks(environment: AppEnvironment) {
        isChecking = true
        var results: [DiagnosticRowData] = []

        // 1. Camera Access & Device
        let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
        let activeDevice = CameraDeviceCatalog.resolvedDevice()?.localizedName ?? "No camera hardware detected"
        let cameraStatus: DiagnosticStatus
        var cameraActionTitle: String? = nil
        var cameraAction: (() -> Void)? = nil

        switch cameraAuth {
        case .authorized:
            cameraStatus = .healthy("Authorized · \(activeDevice)")
        case .denied:
            cameraStatus = .failure("Camera Access Denied")
            cameraActionTitle = "Open Settings"
            cameraAction = {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .restricted:
            cameraStatus = .failure("Restricted by System/MDM Policy")
        case .notDetermined:
            cameraStatus = .warning("Camera Permission Not Determined")
            cameraActionTitle = "Request Access"
            cameraAction = {
                AVCaptureDevice.requestAccess(for: .video) { _ in }
            }
        @unknown default:
            cameraStatus = .warning("Unknown Camera State")
        }
        results.append(DiagnosticRowData(
            id: "camera",
            title: "Camera & Optics",
            iconName: "video.fill",
            status: cameraStatus,
            detail: "Selected optical sensor: \(activeDevice). Required for facial recognition and depth anti-spoofing.",
            actionTitle: cameraActionTitle,
            action: cameraAction
        ))

        // 2. Accessibility Permission
        let accessibilityGranted = AXIsProcessTrusted()
        let accessibilityStatus: DiagnosticStatus
        var accessActionTitle: String? = nil
        var accessAction: (() -> Void)? = nil

        if accessibilityGranted {
            accessibilityStatus = .healthy("Granted")
        } else {
            accessibilityStatus = .failure("Permission Missing")
            accessActionTitle = "Grant Access"
            accessAction = {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        results.append(DiagnosticRowData(
            id: "accessibility",
            title: "Accessibility Permission",
            iconName: "figure.walk",
            status: accessibilityStatus,
            detail: "Required for lock-screen interaction, Touch ID dialog approval, and smooth session unlock.",
            actionTitle: accessActionTitle,
            action: accessAction
        ))

        // 3. Input Monitoring (Scan Key)
        let needsInputMonitoring = NEELxSettings.shared.unlockTriggers.contains(.onSpace)
        let inputMonitoringGranted = SpaceKeyMonitor.hasInputMonitoringAccess()
        let inputStatus: DiagnosticStatus
        var inputActionTitle: String? = nil
        var inputAction: (() -> Void)? = nil

        if inputMonitoringGranted {
            inputStatus = .healthy("Granted")
        } else if needsInputMonitoring {
            inputStatus = .warning("Missing (Scan Key Opted-In)")
            inputActionTitle = "Open Settings"
            inputAction = {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            inputStatus = .healthy("Not Required (Wake/Lock Triggers Only)")
        }
        results.append(DiagnosticRowData(
            id: "input_monitoring",
            title: "Input Monitoring (Scan Key)",
            iconName: "keyboard",
            status: inputStatus,
            detail: "Listens for physical modifier or space keypresses on the lock screen.",
            actionTitle: inputActionTitle,
            action: inputAction
        ))

        // 4. Credential Vault & Touch ID Session
        let hasStoredPassword = SecureCredentialManager.hasStoredPassword()
        let isSessionUnlocked = SecureCredentialManager.isSessionUnlocked
        let isVisualOnly = NEELxSettings.shared.visualOnlyModeEnabled
        let vaultStatus: DiagnosticStatus
        var vaultActionTitle: String? = nil
        var vaultAction: (() -> Void)? = nil

        if isVisualOnly {
            vaultStatus = .healthy("Visual-Only Mode Active (Zero Password)")
        } else if hasStoredPassword {
            if isSessionUnlocked {
                vaultStatus = .healthy("Unlocked & Armed")
            } else {
                vaultStatus = .warning("Session Locked (Touch ID Needed)")
                vaultActionTitle = "Unlock Session"
                vaultAction = {
                    Task { await environment.pocController.unlockSession() }
                }
            }
        } else {
            vaultStatus = .warning("No Password Stored")
            vaultActionTitle = "Set Password"
            vaultAction = {
                OnboardingController.startPasswordOnly()
            }
        }
        results.append(DiagnosticRowData(
            id: "vault",
            title: "Credential Vault & Session",
            iconName: "lock.shield.fill",
            status: vaultStatus,
            detail: isVisualOnly ? "Zero-password visual verification active — user signs in via Touch ID or keyboard." : (hasStoredPassword ? "Password encrypted with AES-GCM in macOS Keychain." : "No password registered yet."),
            actionTitle: vaultActionTitle,
            action: vaultAction
        ))

        // 5. ArcFace Neural Model (512-D)
        let arcFaceTest = ArcFaceEmbedder.testModelLoad()
        let arcFaceStatus: DiagnosticStatus
        var arcFaceActionTitle: String? = nil
        var arcFaceAction: (() -> Void)? = nil

        if arcFaceTest.isBundled && arcFaceTest.isFunctional {
            arcFaceStatus = .healthy("Bundled & Verified (Core ML)")
        } else if arcFaceTest.isBundled && !arcFaceTest.isFunctional {
            arcFaceStatus = .failure("Load Error: \(arcFaceTest.error ?? "Compilation Failed")")
            arcFaceActionTitle = "Troubleshoot"
            arcFaceAction = {
                if let url = URL(string: "https://github.com/\(NEELxConfig.githubRepository)/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            arcFaceStatus = .failure("Missing from Bundle")
            arcFaceActionTitle = "Reinstall App"
            arcFaceAction = {
                if let url = NEELxConfig.officialWebsiteURL {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        results.append(DiagnosticRowData(
            id: "arcface",
            title: "ArcFace Neural Model (512-D)",
            iconName: "person.crop.circle.badge.checkmark",
            status: arcFaceStatus,
            detail: "Primary biometric embedding network. Computes 512-dimensional facial representations.",
            actionTitle: arcFaceActionTitle,
            action: arcFaceAction
        ))

        // 6. Stage 3 3D Neural Depth Model (ANE)
        let depthTest = NeuralDepthAnalyzer.testModelLoad()
        let depthStatus: DiagnosticStatus
        var depthActionTitle: String? = nil
        var depthAction: (() -> Void)? = nil

        if depthTest.isBundled && depthTest.isFunctional {
            depthStatus = .healthy("Operational on Apple Neural Engine (ANE)")
        } else if depthTest.isBundled && !depthTest.isFunctional {
            depthStatus = .failure("Load Error: \(depthTest.error ?? "Failed to initialize")")
            depthActionTitle = "Reload Model"
            depthAction = {
                NeuralDepthAnalyzer.shared.reloadModel()
            }
        } else {
            depthStatus = .warning("Model Not Bundled (Optional)")
            depthActionTitle = "View Setup"
            depthAction = {
                if let url = URL(string: "https://github.com/\(NEELxConfig.githubRepository)#readme") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        results.append(DiagnosticRowData(
            id: "depth",
            title: "3D Neural Depth (Stage 3 ANE)",
            iconName: "cube.transparent.fill",
            status: depthStatus,
            detail: "High-precision 3D depth anti-spoofing powered by DepthAnythingV2 on the Apple Neural Engine.",
            actionTitle: depthActionTitle,
            action: depthAction
        ))

        // 7. Login Item (Launch at Login)
        let smStatus = SMAppService.mainApp.status
        let loginStatus: DiagnosticStatus
        var loginActionTitle: String? = nil
        var loginAction: (() -> Void)? = nil

        switch smStatus {
        case .enabled:
            loginStatus = .healthy("Enabled (Automatic launch on boot)")
        case .requiresApproval:
            loginStatus = .warning("Requires Approval in System Settings")
            loginActionTitle = "Open Settings"
            loginAction = {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .notRegistered:
            loginStatus = .warning("Disabled (Manual Launch Only)")
            loginActionTitle = "Enable"
            loginAction = {
                try? LaunchAtLogin.setEnabled(true)
            }
        case .notFound:
            loginStatus = .warning("Not Registered in ServiceManagement")
        @unknown default:
            loginStatus = .warning("Unknown Status")
        }
        results.append(DiagnosticRowData(
            id: "login_item",
            title: "Launch at Login",
            iconName: "arrow.clockwise.circle.fill",
            status: loginStatus,
            detail: "Ensures NEELx Face Unlock is armed in the background whenever your Mac restarts.",
            actionTitle: loginActionTitle,
            action: loginAction
        ))

        // 8. App Version & Code Signing
        let signing = checkCodeSigning()
        let signingStatus: DiagnosticStatus
        switch signing {
        case .valid(let signer):
            signingStatus = .healthy("Valid Signature (\(signer))")
        case .adHoc:
            signingStatus = .healthy("Development Build (Ad-Hoc Signed)")
        case .unsigned:
            signingStatus = .warning("Unsigned Binary")
        case .invalid(let reason):
            signingStatus = .failure("Signature Invalid: \(reason)")
        }
        results.append(DiagnosticRowData(
            id: "signing",
            title: "App Version & Signing Integrity",
            iconName: "checkmark.seal.fill",
            status: signingStatus,
            detail: "\(NEELxConfig.versionString) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            actionTitle: nil,
            action: nil
        ))

        self.rows = results
        self.lastChecked = Date()
        self.isChecking = false
    }

    private func checkCodeSigning() -> CodeSigningResult {
        var secCode: SecCode?
        guard SecCodeCopySelf([], &secCode) == errSecSuccess, let code = secCode else {
            return .unsigned
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let sCode = staticCode else {
            return .unsigned
        }
        let validity = SecStaticCodeCheckValidity(sCode, SecCSFlags(rawValue: kSecCSDoNotValidateResources), nil)
        if validity != errSecSuccess {
            return .invalid("Code validation error \(validity)")
        }
        var infoDict: CFDictionary?
        if SecCodeCopySigningInformation(sCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoDict) == errSecSuccess,
           let info = infoDict as? [String: Any],
           let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate], !certs.isEmpty {
            var commonName: CFString?
            SecCertificateCopyCommonName(certs[0], &commonName)
            let signerName = (commonName as String?) ?? "Developer Certificate"
            return .valid(signerName)
        }
        return .adHoc
    }

    private enum CodeSigningResult {
        case valid(String)
        case adHoc
        case unsigned
        case invalid(String)
    }

    func generateReportMarkdown() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let dateStr = formatter.string(from: lastChecked ?? Date())

        var md = """
        ### NEELx Setup Diagnostic Report
        - **Timestamp**: \(dateStr)
        - **Overall Health**: \(overallHealthy ? "All Systems Operational" : "\(attentionCount) items need attention")
        - **App Version**: \(NEELxConfig.versionString)
        - **macOS**: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - **Travel Mode**: \(NEELxSettings.shared.isTravelModeActive ? (NEELxSettings.shared.travelModeStatusText ?? "Active") : "Inactive")
        - **Lock and Pause**: \(NEELxSettings.shared.lockAndPauseEnabled ? "Enabled" : "Disabled")
        - **Visual-Only Mode**: \(NEELxSettings.shared.visualOnlyModeEnabled ? "Enabled" : "Disabled")

        #### Diagnostic Checklist:
        """
        for row in rows {
            let symbol: String
            switch row.status {
            case .healthy: symbol = "PASS"
            case .warning: symbol = "WARN"
            case .failure: symbol = "FAIL"
            }
            md += "\n- [\(symbol)] **\(row.title)**: \(row.status.text) — *\(row.detail)*"
        }
        return md
    }

    func copyReportToClipboard() {
        let report = generateReportMarkdown()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        didCopyReport = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.didCopyReport = false
        }
    }
}

struct CheckMySetupSheetView: View {
    let environment: AppEnvironment
    @State private var model = CheckMySetupModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check My Setup")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SettingsMetrics.textPrimary)
                    Text("Comprehensive system health, permissions, and neural model diagnostics.")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    // Overall status banner
                    overallBanner

                    // Checklist cards
                    VStack(spacing: 1) {
                        ForEach(model.rows) { row in
                            diagnosticRow(row)
                        }
                    }
                    .background(SettingsMetrics.rowColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
                    )

                    // Footer actions
                    HStack(spacing: 12) {
                        Button(action: { model.copyReportToClipboard() }) {
                            HStack(spacing: 6) {
                                Image(systemName: model.didCopyReport ? "checkmark" : "doc.on.doc")
                                Text(model.didCopyReport ? "Report Copied!" : "Copy Diagnostic Report")
                            }
                            .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Spacer()

                        Button(action: { model.runChecks(environment: environment) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.trianglehead.clockwise")
                                Text("Re-run Checks")
                            }
                            .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    .padding(.top, 6)
                }
                .padding(20)
            }
        }
        .frame(width: 580, height: 560)
        .background(VisualEffectView().ignoresSafeArea())
        .onAppear {
            model.runChecks(environment: environment)
        }
    }

    private var overallBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: model.overallHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundStyle(model.overallHealthy ? Color(red: 0.19, green: 0.82, blue: 0.35) : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.overallHealthy ? "All Components Verified" : "\(model.attentionCount) Component\(model.attentionCount == 1 ? "" : "s") Need Attention")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsMetrics.textPrimary)
                Text(model.overallHealthy ? "Your Mac is fully configured for fast, secure Face Unlock." : "Use the buttons below to restore missing permissions or reload models.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SettingsMetrics.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(model.overallHealthy ? Color(red: 0.19, green: 0.82, blue: 0.35).opacity(0.12) : Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(model.overallHealthy ? Color(red: 0.19, green: 0.82, blue: 0.35).opacity(0.35) : Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func diagnosticRow(_ row: DiagnosticRowData) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: row.status.iconName)
                    .font(.system(size: 15))
                    .foregroundStyle(row.status.iconColor)
                    .frame(width: 20)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(SettingsMetrics.textPrimary)
                        Spacer()
                        Text(row.status.text)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(row.status.iconColor)
                    }

                    Text(row.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                        .lineLimit(2)

                    if let actionTitle = row.actionTitle, let action = row.action {
                        Button(action: {
                            action()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                model.runChecks(environment: environment)
                            }
                        }) {
                            Text(actionTitle)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
                .padding(.leading, 46)
        }
    }
}
