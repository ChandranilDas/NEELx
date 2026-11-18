//
//  SystemAuthPromptCoordinator.swift
//  NEELx
//
//  iPad Pro / iPhone-style Face ID for macOS system Touch ID & password popups everywhere:
//  System Settings toggles, app/pkg installations, Saved Passwords (Safari/Chrome/Passwords app),
//  Finder admin actions, Keychain prompts, and Terminal `sudo` — while strictly excluding
//  Apple Pay, purchases/payments, web page forms, and NEELx's own session unlock prompt.
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
    private(set) var lastStatus: String = "Watching for macOS Touch ID & password prompts"

    private var monitorTask: Task<Void, Never>?
    private var activeScanTask: Task<Void, Never>?

    /// Cooldown per prompt signature so canceling or touching Touch ID manually never re-triggers the same dialog.
    private var handledPromptKeys: [String: Date] = [:]
    private let promptCooldown: TimeInterval = 12.0

    private nonisolated static let allowedAuthBundleIDs: Set<String> = [
        "com.apple.SecurityAgent",
        "com.apple.LocalAuthentication.UIAgent",
        "com.apple.LocalAuthenticationRemoteService",
        "com.apple.AuthenticationServices.Agent",
        "com.apple.coreservices.uiagent",
        "com.apple.CoreAuthentication",
        "com.apple.UserNotificationCenter",
    ]

    private nonisolated static let allowedAuthOwnerNames: Set<String> = [
        "SecurityAgent",
        "coreautha",
        "CoreAuthentication",
        "LocalAuthentication",
        "LocalAuthenticationRemoteService",
        "AuthenticationServicesAgent",
        "CoreServicesUIAgent",
    ]

    /// High-security / financial prompts that must ALWAYS remain Touch ID / manual password only.
    private nonisolated static let excludedPromptKeywords: [String] = [
        "apple pay",
        "pay with touch id",
        "touch id to pay",
        "double click to pay",
        "confirm payment",
        "payment",
        "purchase",
        "checkout",
        "apple card",
        "card ending",
        "wallet",
        "app store",
        "filevault",
        "recovery key",
        "erase all content",
        "neelx",
    ]

    private struct DetectedAuthPrompt {
        let key: String
        let windowID: CGWindowID?
        let pid: pid_t
        let ownerName: String
        let rootElement: AXUIElement
    }

    init(pocController: POCController) {
        self.pocController = pocController
        startMonitoring()
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
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

        let now = Date()
        handledPromptKeys = handledPromptKeys.filter { now.timeIntervalSince($0.value) < promptCooldown }

        guard let prompt = Self.detectActiveAuthPrompt() else { return }
        if handledPromptKeys[prompt.key] != nil { return }

        handledPromptKeys[prompt.key] = now
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
        guard Self.isPromptStillPresent(prompt) else { return }

        let showsUI = NEELxSettings.shared.effectiveUnlockAnimationStyle != .none
        if showsUI {
            NotchOverlayController.shared.present()
        }
        scanLighting.begin(forEnrollment: false, allowWhenUnlocked: true)

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
            guard Self.isPromptStillPresent(prompt),
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

            // Face verified! Safely transition Touch ID dialog to Password mode (if needed),
            // verify the AXSecureTextField inside that exact auth dialog, and submit.
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
                lastStatus = "Couldn't enter password into \(prompt.ownerName) — use Touch ID manually."
                if showsUI { NotchOverlayController.shared.finish(success: false) }
            }
            return
        }

        if showsUI {
            NotchOverlayController.shared.disarm()
        }
    }

    // MARK: - Safe Accessibility Prompt Approval

    private func approveSystemPrompt(prompt: DetectedAuthPrompt) async -> Bool {
        guard Self.isPromptStillPresent(prompt) else { return false }

        NSRunningApplication(processIdentifier: prompt.pid)?.activate(options: [])

        // Step 1: Locate existing AXSecureTextField, or click "Use Password…" on Touch ID sheet
        var secureField = Self.findSecureTextField(in: prompt.rootElement)
            ?? Self.findSecureTextField(in: AXUIElementCreateApplication(prompt.pid))

        if secureField == nil {
            if let usePasswordBtn = Self.findUsePasswordButton(in: prompt.rootElement)
                ?? Self.findUsePasswordButton(in: AXUIElementCreateApplication(prompt.pid)) {
                AXUIElementPerformAction(usePasswordBtn, kAXPressAction as CFString)
                for _ in 0..<18 {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard Self.isPromptStillPresent(prompt) else { return false }
                    if let found = Self.findSecureTextField(in: prompt.rootElement)
                        ?? Self.findSecureTextField(in: AXUIElementCreateApplication(prompt.pid)) {
                        secureField = found
                        break
                    }
                }
            }
        }

        // Strict safety guard: NEVER type the Mac password unless a verified AXSecureTextField is present!
        guard let targetField = secureField else { return false }
        guard Self.isPromptStillPresent(prompt) else { return false }

        NSRunningApplication(processIdentifier: prompt.pid)?.activate(options: [])
        AXUIElementSetAttributeValue(targetField, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(for: .milliseconds(70))

        guard Self.isPromptStillPresent(prompt) else { return false }

        return await pocController.injectStoredPassword(requireAuthoritativeLock: false)
    }

    // MARK: - Broad System Auth Prompt Detection (with Strict Payment & Web Exclusion)

    private static func detectActiveAuthPrompt() -> DetectedAuthPrompt? {
        // Channel 1: Inspect the currently focused macOS window/sheet via AXSystemWide.
        // Catches Touch ID / Password sheets hosted by coreautha, SecurityAgent, System Settings,
        // Installer, Passwords, Finder, Chrome/Safari system modals, etc.
        if let focusedPrompt = detectFromFocusedSystemWindow() {
            return focusedPrompt
        }

        // Channel 2: Scan all on-screen windows owned by Apple's system authentication agents
        // (covers non-activating floating Touch ID panels).
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
            let isAppleAuth = allowedAuthBundleIDs.contains(bundleID) || allowedAuthOwnerNames.contains(ownerName)
            guard isAppleAuth else { continue }

            if let bounds = info[kCGWindowBounds as String] as? [String: Any],
               let w = bounds["Width"] as? Double,
               let h = bounds["Height"] as? Double,
               (w < 160 || h < 90) {
                continue
            }

            let appRoot = AXUIElementCreateApplication(pid)
            let textBlob = collectDialogText(in: appRoot).lowercased()
            if isExcludedHighSecurityOrPayment(textBlob) { continue }

            let hasField = findSecureTextField(in: appRoot) != nil
            let hasUsePwd = findUsePasswordButton(in: appRoot) != nil
            if hasField || hasUsePwd {
                return DetectedAuthPrompt(
                    key: "win-\(winID)-\(pid)",
                    windowID: winID,
                    pid: pid,
                    ownerName: ownerName,
                    rootElement: appRoot
                )
            }
        }

        return nil
    }

    private static func detectFromFocusedSystemWindow() -> DetectedAuthPrompt? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRef) == .success,
              let focusedApp = focusedAppRef else {
            return nil
        }
        let appElement = focusedApp as! AXUIElement

        var pid: pid_t = 0
        guard AXUIElementGetPid(appElement, &pid) == .success, pid > 0 else { return nil }

        let runningApp = NSRunningApplication(processIdentifier: pid)
        let bundleID = runningApp?.bundleIdentifier ?? ""
        let ownerName = runningApp?.localizedName ?? bundleID

        // Grab focused window or attached modal sheet (e.g. System Settings Touch ID sheet)
        var targetRoot: AXUIElement?
        var focusedWinRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWinRef) == .success,
           let win = focusedWinRef {
            let winEl = win as! AXUIElement
            // Prefer an attached AXSheet if one is currently presented over the window
            var sheetsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(winEl, kAXChildrenAttribute as CFString, &sheetsRef) == .success,
               let children = sheetsRef as? [AXUIElement],
               let sheet = children.first(where: { axString($0, kAXRoleAttribute) == kAXSheetRole }) {
                targetRoot = sheet
            } else {
                targetRoot = winEl
            }
        }
        let root = targetRoot ?? appElement

        // Never touch web page content (prevents ever confusing a website login box with a macOS auth prompt)
        if containsWebArea(in: root) { return nil }

        let textBlob = collectDialogText(in: root).lowercased()
        if isExcludedHighSecurityOrPayment(textBlob) { return nil }

        let isAppleAuthProcess = allowedAuthBundleIDs.contains(bundleID) || allowedAuthOwnerNames.contains(ownerName)
        let hasField = findSecureTextField(in: root) != nil
        let hasUsePwd = findUsePasswordButton(in: root) != nil

        // Trigger if:
        //  (a) It's an Apple authentication daemon with a password field or "Use Password…" button, OR
        //  (b) It's a native macOS Touch ID modal/sheet (contains "touch id" + "use password"/"enter password"/password field)
        let looksLikeTouchIDModal = textBlob.contains("touch id") && (hasUsePwd || hasField)
        let looksLikeAdminPasswordSheet = (axString(root, kAXRoleAttribute) == kAXSheetRole || axString(root, kAXSubroleAttribute) == kAXSystemDialogSubrole)
            && hasField
            && (textBlob.contains("enter your password") || textBlob.contains("allow this") || textBlob.contains("administrator") || textBlob.contains("make changes"))

        guard (isAppleAuthProcess && (hasField || hasUsePwd)) || looksLikeTouchIDModal || looksLikeAdminPasswordSheet else {
            return nil
        }

        let winTitle = axString(root, kAXTitleAttribute) ?? "modal"
        let key = "ax-\(pid)-\(winTitle)-\(textBlob.prefix(48))"
        return DetectedAuthPrompt(
            key: key,
            windowID: nil,
            pid: pid,
            ownerName: ownerName,
            rootElement: root
        )
    }

    private static func isPromptStillPresent(_ prompt: DetectedAuthPrompt) -> Bool {
        if let winID = prompt.windowID {
            guard let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]] else { return false }
            return windowList.contains { info in
                (info[kCGWindowNumber as String] as? CGWindowID) == winID
                    && (info[kCGWindowOwnerPID as String] as? Int32) == prompt.pid
            }
        }
        // AX-detected sheet/dialog: check that either the password field or "Use Password…" button still exists
        return findSecureTextField(in: prompt.rootElement) != nil
            || findUsePasswordButton(in: prompt.rootElement) != nil
            || findSecureTextField(in: AXUIElementCreateApplication(prompt.pid)) != nil
            || findUsePasswordButton(in: AXUIElementCreateApplication(prompt.pid)) != nil
    }

    private static func isExcludedHighSecurityOrPayment(_ lowercasedText: String) -> Bool {
        for keyword in excludedPromptKeywords {
            if lowercasedText.contains(keyword) { return true }
        }
        return false
    }

    private static func containsWebArea(in root: AXUIElement) -> Bool {
        bfsFind(root: root, maxNodes: 80) { el in
            axString(el, kAXRoleAttribute) == "AXWebArea"
        } != nil
    }

    private static func findSecureTextField(in root: AXUIElement) -> AXUIElement? {
        bfsFind(root: root, maxNodes: 180) { el in
            let role = axString(el, kAXRoleAttribute)
            let subrole = axString(el, kAXSubroleAttribute)
            return role == kAXTextFieldRole && subrole == kAXSecureTextFieldSubrole
        }
    }

    private static func findUsePasswordButton(in root: AXUIElement) -> AXUIElement? {
        bfsFind(root: root, maxNodes: 180) { el in
            guard axString(el, kAXRoleAttribute) == kAXButtonRole else { return false }
            let title = (axString(el, kAXTitleAttribute) ?? "").lowercased()
            let desc = (axString(el, kAXDescriptionAttribute) ?? "").lowercased()
            let combined = title + " " + desc
            return combined.contains("use password")
                || combined.contains("enter password")
                || title == "password…"
                || title == "password..."
                || title == "password"
        }
    }

    private static func collectDialogText(in root: AXUIElement) -> String {
        var parts: [String] = []
        var queue: [AXUIElement] = [root]
        var idx = 0
        while idx < queue.count, idx < 120 {
            let current = queue[idx]
            idx += 1
            for attr in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                if let s = axString(current, attr), !s.isEmpty, s.count < 240 {
                    parts.append(s)
                }
            }
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                for child in children where queue.count < 120 {
                    queue.append(child)
                }
            }
            if idx == 1 {
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(current, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let windows = windowsRef as? [AXUIElement] {
                    for win in windows where queue.count < 120 {
                        queue.append(win)
                    }
                }
            }
        }
        return parts.joined(separator: " ")
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
            if idx == 1 {
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(current, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let windows = windowsRef as? [AXUIElement] {
                    for win in windows where queue.count < 120 {
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
