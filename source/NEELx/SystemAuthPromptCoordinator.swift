//
//  SystemAuthPromptCoordinator.swift
//  NEELx
//
//  iPad Pro / iPhone-style Face ID for macOS system Touch ID & password authorization prompts
//  (app installers, System Settings admin locks, Saved Passwords in Safari/Chrome/Passwords app, Keychain).
//
//  Security & Safety Guarantees:
//    1. Strictly allowlisted to Apple's system authentication agents (`SecurityAgent`, `coreautha` /
//       `LocalAuthentication.UIAgent`, `LocalAuthenticationRemoteService`, `CoreServicesUIAgent`).
//    2. Never triggers on NEELx's own Touch ID session unlock prompt.
//    3. Runs full biometric + Stage 3 Neural 3D Depth + Attention verification BEFORE touching the prompt.
//    4. Only types the decrypted password after verifying an active `AXSecureTextField` inside that
//       exact Apple Auth process PID (switching from "Use Password…" automatically if on Touch ID mode),
//       and immediately zeroes the plaintext buffer in memory.
//

import AppKit
import ApplicationServices
import Foundation
import Observation

@Observable
@MainActor
final class SystemAuthPromptCoordinator {
    private let pocController: POCController
    private let camera = CameraManager()
    private let pipeline = FaceRecognitionPipeline()
    private let scanLighting = ScanLightingController()

    private(set) var isScanningPrompt = false
    private(set) var lastStatus: String = "Idle"

    private var monitorTask: Task<Void, Never>?
    private var activeScanTask: Task<Void, Never>?

    /// Cooldown per window ID so dismissing/canceling a prompt never causes a retry loop on the same dialog.
    private var handledWindowIDs: [CGWindowID: Date] = [:]
    private let promptCooldown: TimeInterval = 12.0

    private nonisolated static let allowedBundleIDs: Set<String> = [
        "com.apple.SecurityAgent",
        "com.apple.LocalAuthentication.UIAgent",
        "com.apple.LocalAuthenticationRemoteService",
        "com.apple.AuthenticationServices.Agent",
        "com.apple.coreservices.uiagent",
    ]

    private nonisolated static let allowedOwnerNames: Set<String> = [
        "SecurityAgent",
        "coreautha",
        "LocalAuthenticationRemoteService",
        "AuthenticationServicesAgent",
        "CoreServicesUIAgent",
    ]

    private struct DetectedAuthPrompt: Sendable {
        let windowID: CGWindowID
        let pid: pid_t
        let ownerName: String
        let hasPasswordField: Bool
        let hasUsePasswordButton: Bool
    }

    init(pocController: POCController) {
        self.pocController = pocController
        startMonitoring()
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(450))
                guard let self, !Task.isCancelled else { break }
                self.pollForSystemAuthPrompt()
            }
        }
    }

    private func pollForSystemAuthPrompt() {
        guard !isScanningPrompt,
              NEELxSettings.shared.isFaceUnlockEnabled,
              NEELxSettings.shared.systemAuthPromptsEnabled,
              NEELxSettings.shared.hasCompletedOnboarding,
              SecureCredentialManager.isSessionUnlocked,
              SecureCredentialManager.hasStoredPassword(),
              KeystrokeInjector.isAccessibilityTrusted(),
              !LockMonitor.isScreenActuallyLocked(),
              !FaceEnrollmentStore.shared.activeIdentities.isEmpty else {
            return
        }

        // Never collide with lock-screen or onboarding notch overlay
        let overlay = NotchOverlayController.shared
        guard !overlay.isArmed, overlay.phase == .closed else { return }

        // Prune expired cooldown entries
        let now = Date()
        handledWindowIDs = handledWindowIDs.filter { now.timeIntervalSince($0.value) < promptCooldown }

        guard let prompt = Self.detectActiveAuthPrompt() else { return }
        if handledWindowIDs[prompt.windowID] != nil { return }

        handledWindowIDs[prompt.windowID] = now
        beginPromptAuthentication(for: prompt)
    }

    private func beginPromptAuthentication(for prompt: DetectedAuthPrompt) {
        isScanningPrompt = true
        lastStatus = "Verifying Face ID for \(prompt.ownerName)…"

        activeScanTask?.cancel()
        activeScanTask = Task { [weak self] in
            guard let self else { return }
            await self.runPromptScan(prompt: prompt)
        }
    }

    private func runPromptScan(prompt: DetectedAuthPrompt) async {
        defer {
            camera.stop()
            scanLighting.hide()
            isScanningPrompt = false
        }

        await camera.start()
        guard !Task.isCancelled, camera.errorMessage == nil else { return }
        guard Self.isWindowStillOnScreen(windowID: prompt.windowID, pid: prompt.pid) else { return }

        let showsUI = NEELxSettings.shared.effectiveUnlockAnimationStyle != .none
        if showsUI {
            NotchOverlayController.shared.present()
        }
        scanLighting.begin(forEnrollment: false)

        let deadline = Date().addingTimeInterval(Double(NEELxSettings.shared.faceDetectionSeconds))
        let threshold = NEELxSettings.shared.matchThreshold
        let liveness = LivenessAnalyzer()
        liveness.modeProvider = { NEELxSettings.shared.livenessMode }

        var lastProcessedFrameID: UInt64?
        var lastFaceBox: CGRect?
        var matchedNonSpoofFrames = 0
        var livenessIdentity: UUID?

        while Date() < deadline, !Task.isCancelled {
            // Stop immediately if user already touched Touch ID, typed password, or closed the prompt
            guard Self.isWindowStillOnScreen(windowID: prompt.windowID, pid: prompt.pid),
                  !LockMonitor.isScreenActuallyLocked(),
                  SecureCredentialManager.isSessionUnlocked else {
                if showsUI { NotchOverlayController.shared.disarm() }
                return
            }

            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                try? await Task.sleep(nanoseconds: 25_000_000)
                continue
            }
            lastProcessedFrameID = frame.id

            let pipeline = self.pipeline
            let prevBox = lastFaceBox
            let recognized = await Task.detached(priority: .userInitiated) { () -> (FaceRecognitionResult, LivenessFrame)? in
                guard let result = try? pipeline.recognize(in: frame.image, preferNear: prevBox, requireSingleFace: true) else { return nil }
                let crop = CameraManager.renderCrop(from: frame, imageRect: result.face.boundingBox)
                return (result, LivenessFeatureExtractor.extract(from: result, frame: frame.image, faceCrop: crop))
            }.value

            guard let (result, livenessFrame) = recognized else {
                scanLighting.consider(frame.image, faceVisible: false, faceBox: nil)
                lastFaceBox = nil
                matchedNonSpoofFrames = 0
                liveness.reset()
                continue
            }

            scanLighting.consider(frame.image, faceVisible: true, faceBox: result.face.normalizedBoundingBox)
            lastFaceBox = result.face.normalizedBoundingBox

            let scored = pipeline.score(result.embedding, against: FaceEnrollmentStore.shared.activeIdentities)
            guard let matched = pipeline.bestMatch(in: scored, threshold: threshold) else {
                matchedNonSpoofFrames = 0
                liveness.reset()
                continue
            }

            if livenessIdentity != matched.identity.id {
                liveness.reset()
                matchedNonSpoofFrames = 0
                livenessIdentity = matched.identity.id
            }

            // Stage 3 Neural 3D Depth anti-spoofing
            let depthReading: NeuralDepthReading?
            let effectiveFrame: LivenessFrame
            if NEELxSettings.shared.neuralDepthEnabled {
                let faceBox = result.face.normalizedBoundingBox
                let noseCenter = LivenessFeatureExtractor.normalizedNoseCenter(for: result.face)
                depthReading = await Task.detached(priority: .userInitiated) {
                    NeuralDepthAnalyzer.shared.analyze(
                        frame: frame.image,
                        normalizedFaceBox: faceBox,
                        noseNormalizedCenter: noseCenter
                    )
                }.value
                effectiveFrame = LivenessFrame(
                    timestamp: livenessFrame.timestamp,
                    landmarks: livenessFrame.landmarks,
                    interocularDistance: livenessFrame.interocularDistance,
                    yaw: livenessFrame.yaw,
                    leftEyeAspectRatio: livenessFrame.leftEyeAspectRatio,
                    rightEyeAspectRatio: livenessFrame.rightEyeAspectRatio,
                    noseOffsetRatio: livenessFrame.noseOffsetRatio,
                    hasReliableLandmarks: livenessFrame.hasReliableLandmarks,
                    deviceOverlapFraction: livenessFrame.deviceOverlapFraction,
                    glare: livenessFrame.glare,
                    neuralDepth: depthReading
                )
            } else {
                depthReading = nil
                effectiveFrame = livenessFrame
            }

            // Attention & Gaze check
            let isFacingScreen = (result.face.yaw.map { abs($0) <= 0.45 } ?? true) &&
                                 (result.face.pitch.map { abs($0) <= 0.45 } ?? true)
            let eyesOpen = (effectiveFrame.leftEyeAspectRatio ?? 0.25 >= 0.11) &&
                           (effectiveFrame.rightEyeAspectRatio ?? 0.25 >= 0.11)
            let attentionVerified = isFacingScreen && eyesOpen

            let snapshot = liveness.observe(effectiveFrame)
            if snapshot.decision.isDenied {
                let reason = snapshot.decision.denialReason ?? "Spoof blocked on system prompt."
                lastStatus = reason
                SecurityAuditLog.shared.record(kind: .spoofBlocked, detail: "\(prompt.ownerName): \(reason)", snapshotImage: frame.image)
                if showsUI { NotchOverlayController.shared.finish(success: false) }
                return
            }

            let enrolledBaseline = matched.identity.depthBaseline
            let personalFlatSpoof: Bool = {
                guard let reading = depthReading,
                      let baseline = enrolledBaseline,
                      baseline.medianNoseProtrusion >= 0.025 else { return false }
                return reading.noseProtrusion < baseline.medianNoseProtrusion * 0.22
                    && reading.planarityResidual < 0.024
            }()
            let flatSpoofSuspected = (depthReading?.flatSpoofScore ?? 0) >= LivenessTuning.default.flatDepthSpoofLevel
                || personalFlatSpoof
            if !flatSpoofSuspected {
                matchedNonSpoofFrames += 1
            } else {
                matchedNonSpoofFrames = 0
                continue
            }

            let depthProfileSimilarity: Float? = {
                guard let liveSig = depthReading?.depthSignature,
                      let enrolledProfile = matched.identity.depthProfile else { return nil }
                return NeuralDepthAnalyzer.signatureSimilarity(liveSig, enrolledProfile)
            }()

            let livenessConfirmed: Bool
            if snapshot.decision.isConfirmed {
                livenessConfirmed = true
            } else if let depthReading {
                let profileMatches = depthProfileSimilarity.map { $0 >= 0.40 } ?? false
                let baselineMatches = enrolledBaseline.map {
                    $0.medianNoseProtrusion >= 0.020 && depthReading.noseProtrusion >= $0.medianNoseProtrusion * 0.55
                } ?? false
                let reliefConfirmed = depthReading.depth3DScore >= LivenessTuning.default.neuralDepth3DLevel || baselineMatches
                livenessConfirmed = attentionVerified && (reliefConfirmed || profileMatches || matchedNonSpoofFrames >= 2)
            } else {
                livenessConfirmed = attentionVerified && matchedNonSpoofFrames >= 2
            }

            guard livenessConfirmed, attentionVerified else { continue }

            // Face verified! Now safely switch Touch ID modal to password field (if needed), verify
            // the AXSecureTextField belongs to this exact Apple Auth PID, and submit.
            let approved = await approveSystemPrompt(prompt: prompt)
            if approved {
                let depthNote = depthReading.map { String(format: "3D Depth %.0f%% (%.0fms ANE)", $0.depth3DScore * 100, $0.inferenceMs) }
                    ?? "Attention & Biometrics Verified"
                let detail = "Approved system prompt (\(prompt.ownerName)) — Matched \(matched.identity.name) at \(String(format: "%.3f", matched.centroidSimilarity)), \(depthNote)."
                lastStatus = detail
                SecurityAuditLog.shared.record(kind: .unlocked, detail: detail)
                if showsUI { NotchOverlayController.shared.finish(success: true) }
                if NEELxSettings.shared.hapticFeedbackEnabled {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            } else {
                lastStatus = "Couldn't enter password into \(prompt.ownerName) — use Touch ID or password manually."
                if showsUI { NotchOverlayController.shared.finish(success: false) }
            }
            return
        }

        // Timed out without matching — retract cleanly so user can use Touch ID undisturbed
        if showsUI {
            NotchOverlayController.shared.disarm()
        }
    }

    // MARK: - Safe Accessibility Prompt Approval

    /// Switches a Touch ID prompt to password entry (if needed), verifies an `AXSecureTextField`
    /// inside the exact allowlisted Apple Auth PID, focuses it, and injects the decrypted password + Return.
    private func approveSystemPrompt(prompt: DetectedAuthPrompt) async -> Bool {
        guard Self.isWindowStillOnScreen(windowID: prompt.windowID, pid: prompt.pid) else { return false }

        // Ensure the Apple Auth dialog is active so keystrokes land inside it
        NSRunningApplication(processIdentifier: prompt.pid)?.activate(options: [])

        // Step 1: Locate existing password field, OR press "Use Password…" button on Touch ID sheet
        var secureField = Self.findSecureTextField(inPID: prompt.pid)
        if secureField == nil {
            if let usePasswordBtn = Self.findUsePasswordButton(inPID: prompt.pid) {
                AXUIElementPerformAction(usePasswordBtn, kAXPressAction as CFString)
                // Wait up to 800ms for the Touch ID modal to transition to the password text field
                for _ in 0..<16 {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard Self.isWindowStillOnScreen(windowID: prompt.windowID, pid: prompt.pid) else { return false }
                    if let found = Self.findSecureTextField(inPID: prompt.pid) {
                        secureField = found
                        break
                    }
                }
            }
        }

        // Strict safety guard: NEVER type the user's password unless we verified an actual AXSecureTextField
        // inside the allowlisted Apple Authentication Agent process!
        guard let targetField = secureField else { return false }
        guard Self.isWindowStillOnScreen(windowID: prompt.windowID, pid: prompt.pid) else { return false }

        NSRunningApplication(processIdentifier: prompt.pid)?.activate(options: [])
        AXUIElementSetAttributeValue(targetField, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(for: .milliseconds(70))

        guard Self.isWindowStillOnScreen(windowID: prompt.windowID, pid: prompt.pid) else { return false }

        return await pocController.injectStoredPassword(requireAuthoritativeLock: false)
    }

    // MARK: - Window & Accessibility Inspection (Strict Apple-Only Allowlist)

    private static func detectActiveAuthPrompt() -> DetectedAuthPrompt? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let pidNum = info[kCGWindowOwnerPID as String] as? Int32,
                  let winID = info[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }

            let pid = pid_t(pidNum)
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
            guard allowedBundleIDs.contains(bundleID) || allowedOwnerNames.contains(ownerName) else {
                continue
            }

            // Ignore tiny invisible helper windows or status items
            if let bounds = info[kCGWindowBounds as String] as? [String: Any],
               let w = bounds["Width"] as? Double,
               let h = bounds["Height"] as? Double,
               (w < 180 || h < 100) {
                continue
            }

            // Never intercept NEELx's own Touch ID session unlock prompt
            if dialogMentionsNEELx(pid: pid) {
                continue
            }

            let hasField = findSecureTextField(inPID: pid) != nil
            let hasUsePwd = findUsePasswordButton(inPID: pid) != nil
            if hasField || hasUsePwd {
                return DetectedAuthPrompt(
                    windowID: winID,
                    pid: pid,
                    ownerName: ownerName,
                    hasPasswordField: hasField,
                    hasUsePasswordButton: hasUsePwd
                )
            }
        }
        return nil
    }

    private static func isWindowStillOnScreen(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        return windowList.contains { info in
            let w = info[kCGWindowNumber as String] as? CGWindowID
            let p = info[kCGWindowOwnerPID as String] as? Int32
            return w == windowID && p == pid
        }
    }

    private static func findSecureTextField(inPID pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        return bfsFind(root: app, maxNodes: 160) { el in
            let role = axString(el, kAXRoleAttribute)
            let subrole = axString(el, kAXSubroleAttribute)
            return role == kAXTextFieldRole && subrole == kAXSecureTextFieldSubrole
        }
    }

    private static func findUsePasswordButton(inPID pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        return bfsFind(root: app, maxNodes: 160) { el in
            guard axString(el, kAXRoleAttribute) == kAXButtonRole else { return false }
            let title = (axString(el, kAXTitleAttribute) ?? "").lowercased()
            let desc = (axString(el, kAXDescriptionAttribute) ?? "").lowercased()
            let combined = title + " " + desc
            return combined.contains("use password") || combined.contains("enter password")
        }
    }

    private static func dialogMentionsNEELx(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        return bfsFind(root: app, maxNodes: 120) { el in
            let text = [
                axString(el, kAXValueAttribute),
                axString(el, kAXTitleAttribute),
                axString(el, kAXDescriptionAttribute),
            ].compactMap { $0 }.joined(separator: " ").lowercased()
            return text.contains("neelx")
        } != nil
    }

    private static func bfsFind(
        root: AXUIElement,
        maxNodes: Int,
        predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var idx = 0
        while idx < queue.count, idx < maxNodes {
            let current = queue[idx]
            idx += 1
            if idx > 1 && predicate(current) {
                return current
            }
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                for child in children where queue.count < maxNodes {
                    queue.append(child)
                }
            }
            // Also check AXWindows on the root application element
            if idx == 1 {
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(current, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let windows = windowsRef as? [AXUIElement] {
                    for win in windows where queue.count < maxNodes {
                        queue.append(win)
                    }
                }
            }
        }
        return nil
    }

    private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
