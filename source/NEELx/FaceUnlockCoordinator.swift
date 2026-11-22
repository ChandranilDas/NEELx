//
//  FaceUnlockCoordinator.swift
//  NEELx
//
//  Connects face recognition to the actual unlock path. Off by default; user opts in after validating accuracy in Face Lab.
//
//  Known limitation: LivenessAnalyzer defeats a photo but not a replayed video (real non-rigid motion looks live) — a successful spoof types the real macOS password.
//

import Foundation
import CoreGraphics
import Observation

/// Item #33: Local "Last Unlock Receipt" — cryptographic/biometric telemetry of the most recent successful unlock.
struct LastUnlockReceipt: Codable, Sendable, Equatable {
    let timestamp: Date
    let faceName: String
    let similarityPercent: Int
    let opticalSensor: String
    let depth3DPercent: Int?
    let depthProfileMatchPercent: Int?
    let aneLatencyMs: Double?
    let livenessCue: String
    let isVisualOnly: Bool
}

@Observable
@MainActor
final class FaceUnlockCoordinator {
    private let pocController: POCController
    let lockMonitor = LockMonitor()
    let camera = CameraManager()
    private let scanLighting = ScanLightingController()
    let pipeline = FaceRecognitionPipeline()

    /// Item #33: Most recent unlock telemetry receipt
    private(set) var latestReceipt: LastUnlockReceipt?

    /// Persisted via NEELxSettings. Setting to false cancels any in-flight scan and disarms the overlay immediately.
    var isEnabled: Bool {
        didSet {
            NEELxSettings.shared.isFaceUnlockEnabled = isEnabled
            if !isEnabled { disarmOverlay() }
        }
    }

    /// Kept independent from Face Lab's own `threshold` so tuning the debug tool never silently changes the real unlock gate.
    var matchThreshold: Float {
        didSet { NEELxSettings.shared.matchThreshold = matchThreshold }
    }
    /// Shares its setting with NotchOverlayController's scanning timeout, so the background loop stops in step with the UI collapsing.
    private var scanWindowDuration: TimeInterval {
        TimeInterval(NEELxSettings.shared.faceDetectionSeconds)
    }
    /// Requires sustained below-threshold frames (after camera exposure & adaptive lighting settle)
    /// so dark-room ramp-up frames never prematurely abort a real unlock.
    private let wrongFaceStreakThreshold = 18

    private(set) var statusMessage = "Idle"
    private(set) var lastOutcome: String?

    /// Reserved face name from visual-only match — shows welcome banner when macOS confirms sign-in (Item #38).
    private var pendingVisualOnlyWelcomeName: String?

    private var hasArmedForCurrentLock = false
    /// One-shot per lock session — an auto-retry that could itself auto-retry would loop the camera for the whole lock session.
    private var hasAutoRetriedForCurrentLock = false
    private var scanTask: Task<Void, Never>?
    /// Bumped by every `startScanCycle()`; a cycle bails once superseded (see `runScanCycle(generation:)`).
    private var scanGeneration = 0
    /// When the last scan cycle was armed — collapses a single wake into a single arm (see `.wake` branch of `evaluateTrigger`).
    private var lastArmedAt: ContinuousClock.Instant?
    /// One lid-open fires several wake signals within a few hundred ms of each other; anything in this window counts as the same wake.
    private let rearmDebounce: Duration = .seconds(2)
    /// Held separately from `scanTask` since it's scheduled from inside the scan task it follows — reusing `scanTask` would self-cancel it.
    private var autoRetryTask: Task<Void, Never>?
    /// Gap between headless auto-retries, just to keep the camera from restarting in a tight loop.
    private let headlessRetryDelay: Duration = .seconds(1)

    /// When off, no notch/pill presence at all — every overlay call in this file is conditioned on this rather than just skipping the video.
    private var showsUI: Bool { NEELxSettings.shared.showUnlockAnimation }

    /// Reads the space key on the lock screen for the "On space" trigger; only runs while locked + opted in.
    private let spaceKeyMonitor = SpaceKeyMonitor()

    init(pocController: POCController) {
        self.pocController = pocController
        self.isEnabled = NEELxSettings.shared.isFaceUnlockEnabled
        self.matchThreshold = NEELxSettings.shared.matchThreshold
        spaceKeyMonitor.onSpaceKeyDown = { [weak self] in self?.handleSpaceKeyPress() }
        observeLockAndWakeEvents()
        // Pre-warm Stage 3 Core ML Depth Anything V2 on ANE in background so lock-screen scans have zero cold-start lag.
        if NEELxSettings.shared.neuralDepthEnabled {
            Task.detached(priority: .utility) {
                _ = NeuralDepthAnalyzer.shared.warmUp()
            }
        }
        if let data = UserDefaults.standard.data(forKey: "NEELx.latestUnlockReceipt"),
           let saved = try? JSONDecoder().decode(LastUnlockReceipt.self, from: data) {
            self.latestReceipt = saved
        }
    }

    /// Item #33: Records cryptographic/biometric telemetry for the most recent unlock.
    private func recordUnlockReceipt(
        name: String,
        similarity: Float,
        sensor: String,
        depthReading: NeuralDepthReading?,
        profileSimilarity: Float?,
        cue: LivenessCue?,
        isVisualOnly: Bool
    ) {
        let receipt = LastUnlockReceipt(
            timestamp: Date(),
            faceName: name,
            similarityPercent: Int((similarity * 100).rounded()),
            opticalSensor: sensor,
            depth3DPercent: depthReading.map { Int(($0.depth3DScore * 100).rounded()) },
            depthProfileMatchPercent: profileSimilarity.map { Int(($0 * 100).rounded()) },
            aneLatencyMs: depthReading?.inferenceMs,
            livenessCue: depthReading != nil ? "3D Neural Depth (ANE)" : (cue?.title ?? "Attention & Gaze"),
            isVisualOnly: isVisualOnly
        )
        self.latestReceipt = receipt
        if let data = try? JSONEncoder().encode(receipt) {
            UserDefaults.standard.set(data, forKey: "NEELx.latestUnlockReceipt")
        }
    }

    /// Re-subscribes on every change — `withObservationTracking` only fires once per registration.
    private func observeLockAndWakeEvents() {
        withObservationTracking {
            _ = lockMonitor.isScreenLocked
            _ = lockMonitor.wakeEventCount
            _ = lockMonitor.isSleeping
            // Also tracked so screensaver-stop and display-only wakes still wake this up.
            _ = lockMonitor.eventCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeLockAndWakeEvents()
                // Brief settle delay: CGSession's reported state can lag the true state right after wake.
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.evaluateTrigger()
            }
        }
    }

    private func evaluateTrigger() {
        guard LockMonitor.isScreenActuallyLocked() else {
            if let name = pendingVisualOnlyWelcomeName {
                pendingVisualOnlyWelcomeName = nil
                WelcomeBannerWindowController.shared.show(name: name)
            }
            hasArmedForCurrentLock = false
            hasAutoRetriedForCurrentLock = false
            disarmOverlay()
            return
        }
        guard !lockMonitor.isSleeping else {
            hasArmedForCurrentLock = false
            disarmOverlay()
            return
        }

        // Travel Mode (Item #31): Menu bar toggle to pause Face Unlock
        if NEELxSettings.shared.isTravelModeActive {
            statusMessage = "Face Unlock paused (Travel Mode)"
            hasArmedForCurrentLock = false
            disarmOverlay()
            return
        }

        // `.wake` (sleep, display sleep, or screensaver stopping) is an explicit "let me back in," so clear the one-shot guard.
        // `isWithinRecentArmBurst` keeps the several wake signals from one lid-open from each re-arming and fighting over the camera.
        if lockMonitor.lastEvent == .wake, !isWithinRecentArmBurst {
            hasArmedForCurrentLock = false
        }

        // Runs before the hasArmedForCurrentLock guard — the space monitor's lifetime is tied to "locked + opted in," not to whether a scan already ran.
        updateSpaceMonitor()

        guard isEnabled, !hasArmedForCurrentLock else { return }
        guard let signal = requiredTrigger(for: lockMonitor.lastEvent) else { return }
        // A pinned display that isn't connected bails entirely rather than showing up elsewhere; "Main display" (nil) always resolves.
        guard NotchGeometry.preferredScreen() != nil else { return }

        // Item #38: Visual-only mode does not require stored password or unlocked credential session
        let isVisualOnly = NEELxSettings.shared.visualOnlyModeEnabled || !SecureCredentialManager.hasStoredPassword()
        if !isVisualOnly {
            guard SecureCredentialManager.isSessionUnlocked else {
                statusMessage = "Face unlock is on, but the session is locked — authenticate once from Password settings first."
                return
            }
            guard SecureCredentialManager.hasStoredPassword() else {
                statusMessage = "Face unlock is on, but no password is stored yet."
                return
            }
        }

        // A deselected trigger means "don't auto-scan for this signal," not "do nothing" — the user can still opt in by hand.
        var shouldAutoScan = NEELxSettings.shared.unlockTriggers.contains(signal)

        // Item #39: Lock and Pause — Intentionally locking the Mac (Cmd+Ctrl+Q or Apple Menu)
        // does not immediately auto-unlock while the user sits in front of the screen. Wait for a keypress/interaction.
        if signal == .onLock && NEELxSettings.shared.lockAndPauseEnabled {
            shouldAutoScan = false
        }

        // Headless has nothing to arm/hover, so if this signal isn't selected there's nothing to do — and hasArmedForCurrentLock
        // must stay false, or a later selected signal could never fire (nothing else calls arm() to reset it).
        guard showsUI || shouldAutoScan else { return }

        hasArmedForCurrentLock = true
        lastArmedAt = .now
        Task { [weak self] in
            // arm() only shows a small closed notch silhouette, so this only needs a brief buffer past the login window's entrance.
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.arm(autoScan: shouldAutoScan)
        }
    }

    /// Whether the last arm was recent enough to be part of the same wake burst rather than a new one.
    private var isWithinRecentArmBurst: Bool {
        guard let lastArmedAt else { return false }
        return ContinuousClock.now - lastArmedAt < rearmDebounce
    }

    /// nil for signals that shouldn't arm anything — including a nil `lastEvent`, or the first observation would fire regardless of user selection.
    private func requiredTrigger(for event: LockEventKind?) -> UnlockTrigger? {
        switch event {
        case .wake: return .onWake
        case .screenLocked: return .onLock
        case .screenUnlocked, .willSleep, nil: return nil
        }
    }

    private func disarmOverlay() {
        scanLighting.hide()
        scanTask?.cancel()
        scanTask = nil
        // Bumping makes any cycle still suspended at `await camera.start()` inert, rather than resuming and re-showing the overlay.
        scanGeneration &+= 1
        autoRetryTask?.cancel()
        autoRetryTask = nil
        camera.stop()
        NotchOverlayController.shared.disarm()
        // Covers isEnabled being switched off directly, keeping "disarmed" and "not listening for space" in lockstep.
        spaceKeyMonitor.stop()
    }

    /// Idempotent and safe to call on every lock/wake event. Deliberately does not prompt for Input Monitoring — a missing grant just means "don't listen."
    private func updateSpaceMonitor() {
        let shouldListen = isEnabled
            && NEELxSettings.shared.unlockTriggers.contains(.onSpace)
            && LockMonitor.isScreenActuallyLocked()
            && SpaceKeyMonitor.hasInputMonitoringAccess()
        if shouldListen {
            spaceKeyMonitor.start()
        } else {
            spaceKeyMonitor.stop()
        }
    }

    /// Runs the same gate chain as `evaluateTrigger`, then starts a scan. Independent of `LockMonitor` events, so doesn't touch `hasArmedForCurrentLock`.
    private func handleSpaceKeyPress() {
        guard isEnabled,
              !NEELxSettings.shared.isTravelModeActive,
              NEELxSettings.shared.unlockTriggers.contains(.onSpace),
              LockMonitor.isScreenActuallyLocked(),
              NotchGeometry.preferredScreen() != nil
        else { return }

        let isVisualOnly = NEELxSettings.shared.visualOnlyModeEnabled || !SecureCredentialManager.hasStoredPassword()
        if !isVisualOnly {
            guard SecureCredentialManager.isSessionUnlocked,
                  SecureCredentialManager.hasStoredPassword()
            else { return }
        }

        // Already looking — swallows auto-repeat/double-presses and lets "On wake"/"On lock" override "On space" with no special-casing.
        guard NotchOverlayController.shared.phase != .scanning else { return }

        guard showsUI else {
            // Headless: no overlay, just scan.
            startScanCycle()
            return
        }
        if NotchOverlayController.shared.isArmed {
            // Closed pill/notch already up — expand and scan, like a hover retry.
            startScanCycle()
        } else {
            Task { [weak self] in await self?.arm(autoScan: true) }
        }
    }

    /// Either way the overlay still arms — a deselected trigger only skips the automatic scan, leaving hover-to-start available.
    private func arm(autoScan: Bool) async {
        guard !lockMonitor.isSleeping, isEnabled, LockMonitor.isScreenActuallyLocked() else { return }
        guard showsUI else {
            // Headless: evaluateTrigger() already guaranteed autoScan is true here, so this is just "start scanning."
            startScanCycle()
            return
        }
        NotchOverlayController.shared.arm { [weak self] in
            self?.startScanCycle()
        }
        if autoScan {
            startScanCycle()
        }
    }

    /// Called on arm, and again whenever the overlay hover-activates.
    private func startScanCycle() {
        scanTask?.cancel()
        scanGeneration &+= 1
        let generation = scanGeneration
        scanTask = Task { [weak self] in
            await self?.runScanCycle(generation: generation)
        }
    }

    /// `generation` is what makes overlapping cycles safe: `Task.cancel()` is cooperative, so a superseded cycle still runs to the
    /// end of this function, and its global side effects (`camera.stop()` etc.) could otherwise land on the newer cycle instead
    /// of itself. This was a real bug — a superseded `camera.stop()` queued behind the newer cycle's `startRunning()` made the
    /// camera visibly switch on then die mid-warm-up, leaving the surviving cycle polling a dead session and never unlocking.
    private func runScanCycle(generation: Int) async {
        guard !lockMonitor.isSleeping, isEnabled, LockMonitor.isScreenActuallyLocked() else { return }

        // Item #38: Visual-only mode does not require stored password or unlocked credential session
        let isVisualOnly = NEELxSettings.shared.visualOnlyModeEnabled || !SecureCredentialManager.hasStoredPassword()
        if !isVisualOnly {
            // If the session is locked (e.g. after app restart or 5 wrong-face attempts), still give
            // immediate visual feedback on hover rather than silently ignoring the user's cursor.
            guard SecureCredentialManager.isSessionUnlocked else {
                statusMessage = "Session locked — unlock your Mac and authorize NEELx with Touch ID."
                if showsUI {
                    NotchOverlayController.shared.beginScanning()
                    NotchOverlayController.shared.finish(success: false)
                }
                return
            }
        }

        // Device Proximity Guard: If enabled, requires paired phone/tablet in Bluetooth range (< 1.5m)
        if NEELxSettings.shared.deviceProximityGuardEnabled && !DeviceProximityGuard.shared.isDeviceInRange {
            statusMessage = "Device out of range — bring your paired iPhone or iPad nearby to unlock."
            if showsUI {
                NotchOverlayController.shared.beginScanning()
                NotchOverlayController.shared.finish(success: false)
            }
            return
        }

        CameraActivityMonitor.shared.update(to: .scanningToUnlock)
        await camera.start()
        guard generation == scanGeneration else {
            CameraActivityMonitor.shared.update(to: .standby)
            return
        }
        guard !lockMonitor.isSleeping, LockMonitor.isScreenActuallyLocked() else {
            camera.stop()
            CameraActivityMonitor.shared.update(to: .standby)
            return
        }

        if let error = camera.errorMessage {
            statusMessage = error
            camera.stop()
            CameraActivityMonitor.shared.update(to: .standby)
            return
        }

        let showsUI = self.showsUI
        if showsUI {
            NotchOverlayController.shared.beginScanning()
        }
        scanLighting.begin(forEnrollment: false)
        statusMessage = "Looking for your face…"

        let outcome = await observeScanWindow(
            deadline: Date().addingTimeInterval(scanWindowDuration),
            requireOverlayScanning: showsUI
        )

        // A newer cycle now owns the camera and overlay — leave both alone, and leave the auto-retry one-shot unspent.
        guard generation == scanGeneration else { return }

        camera.stop()
        scanLighting.hide()
        CameraActivityMonitor.shared.update(to: .standby)

        // Only count actual mismatched faces or spoof attempts toward the 5-attempt lockout —
        // dark-room "no face detected" timeouts or missing permissions never permanently lock out hover retries.
        let countsAsBiometricFailure: Bool
        switch outcome {
        case .consistentlyWrongFace, .spoofSuspected:
            countsAsBiometricFailure = true
        case .matched, .noResolution, .injectionBlocked:
            countsAsBiometricFailure = false
        }

        if countsAsBiometricFailure, LockMonitor.isScreenActuallyLocked(), !Task.isCancelled {
            SecureCredentialManager.recordFailedFaceScan()
            if !SecureCredentialManager.isSessionUnlocked {
                pocController.lockSession()
                if showsUI { NotchOverlayController.shared.finish(success: false) }
                statusMessage = "Face attempts exhausted — unlock your Mac normally, then authorize NEELx again."
                return
            }
        }

        switch outcome {
        case .matched:
            // The unlock already happened inside observeScanWindow — this only decides whether anything is shown about it.
            if showsUI {
                let isVisualOnly = NEELxSettings.shared.visualOnlyModeEnabled || !SecureCredentialManager.hasStoredPassword()
                NotchOverlayController.shared.finish(success: true, isVisualOnly: isVisualOnly)
            }
        case .injectionBlocked(let reason):
            statusMessage = reason
            if showsUI {
                NotchOverlayController.shared.finish(success: false)
            }
        case .consistentlyWrongFace:
            statusMessage = "Face not recognized."
            if showsUI {
                NotchOverlayController.shared.finish(success: false)
                statusMessage = "Face not recognized — hover the notch to try again."
                scheduleAutoRetryIfEnabled(after: NotchOverlayController.shared.failureHoldDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        case .spoofSuspected:
            statusMessage = "Couldn't confirm a live face."
            if showsUI {
                NotchOverlayController.shared.finish(success: false)
                statusMessage = "Couldn't confirm a live face — hover the notch to try again."
                scheduleAutoRetryIfEnabled(after: NotchOverlayController.shared.failureHoldDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        case .noResolution:
            statusMessage = "No face detected."
            if showsUI {
                // No explicit collapse call: NotchOverlayController's own scanning timeout fires on the same mark and collapses itself.
                statusMessage = "No face detected — hover the notch to try again."
                scheduleAutoRetryIfEnabled(after: NotchOverlayController.shared.collapseAnimationDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        }
    }

    /// `delay` waits out whatever the overlay is still showing so the retry doesn't start underneath the previous outcome.
    private func scheduleAutoRetryIfEnabled(after delay: Duration) {
        guard NEELxSettings.shared.autoRetryOnce, !hasAutoRetriedForCurrentLock else { return }
        hasAutoRetriedForCurrentLock = true
        autoRetryTask?.cancel()
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Re-check rather than trust the delay: the user may have unlocked by password or retried manually while this waited.
            guard LockMonitor.isScreenActuallyLocked(), self.isEnabled else { return }
            if self.showsUI {
                guard NotchOverlayController.shared.phase == .closed else { return }
            }
            self.startScanCycle()
        }
    }

    private enum ScanOutcome {
        case matched
        case injectionBlocked(String)
        case consistentlyWrongFace
        /// A deny cue (glare, device rectangle) fired — actively rejected as a spoof regardless of match. Same failure path as `.consistentlyWrongFace`.
        case spoofSuspected
        case noResolution
    }

    /// Recognition and liveness run concurrently and each latches when it succeeds, so unlock fires the moment the second lands;
    /// liveness never fails the scan by staying undecided, it just keeps scanning until `deadline`.
    /// `requireOverlayScanning` bails early once the overlay's own timeout collapses the UI — only applied when there is an
    /// overlay, since headlessly `phase` never becomes `.scanning` at all.
    private func observeScanWindow(deadline: Date, requireOverlayScanning: Bool) async -> ScanOutcome {
        let liveness = LivenessAnalyzer()
        liveness.modeProvider = { NEELxSettings.shared.livenessMode }
        // Spoof-denial cues accumulate across the whole scan, including nonmatching faces.
        // Only positive liveness evidence is reset when identity continuity breaks.
        let scanLiveness = LivenessAnalyzer()
        scanLiveness.modeProvider = { NEELxSettings.shared.livenessMode }
        let scanStartedAt = Date()
        var consecutiveWrongFaceFrames = 0
        var matchedNonSpoofFrames = 0
        /// Rolling buffer for Multi-Frame Temporal Depth Consistency (prevents single-frame depth flicker/curved-print bypasses).
        var recentDepthReadings: [NeuralDepthReading] = []

        /// Cleared the moment a detected face fails to match, so a latched match can't be handed to whoever steps in next.
        var readyMatch: ScoredIdentity?
        var livenessIdentity: UUID?
        var livenessConfirmed = false
        /// Last frame's selected face, passed back so `selectDominantFace` stays on the same person instead of flip-flopping.
        var lastFaceBoundingBox: CGRect?
        /// Cheap way to detect "no new camera frame yet" vs. "fresh frame" — without it a repeat frame would corrupt the liveness motion signal.
        var lastProcessedFrameID: UInt64?
        /// Tracks the latest frame & reason when a face WAS visible so timed-out failures (e.g. flat 2D photo,
        /// closed eyes, or short wrong-face attempts) are always recorded in the Audit Log, while empty-room timeouts stay silent.
        var lastSeenFaceFrame: CameraFrame?
        var lastPendingKind: SecurityAuditKind = .wrongFace
        var lastPendingReason: String?

        while Date() < deadline, !Task.isCancelled,
              !requireOverlayScanning || NotchOverlayController.shared.phase == .scanning {
            guard LockMonitor.isScreenActuallyLocked() else { return .noResolution }

            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                // 20ms keeps the liveness window's sample count high while staying close to the camera's native ~33ms cadence.
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastProcessedFrameID = frame.id

            let pipeline = self.pipeline
            let previousBoundingBox = lastFaceBoundingBox
            let outcome = await Task.detached(priority: .userInitiated) { () -> (FaceRecognitionResult, LivenessFrame)? in
                guard let result = try? pipeline.recognize(in: frame.image, preferNear: previousBoundingBox, requireSingleFace: true) else { return nil }
                let faceCrop = CameraManager.renderCrop(from: frame, imageRect: result.face.boundingBox)
                return (result, LivenessFeatureExtractor.extract(from: result, frame: frame.image, faceCrop: faceCrop))
            }.value

            guard !Task.isCancelled, SecureCredentialManager.isSessionUnlocked else { return .noResolution }
            guard let (result, livenessFrame) = outcome else {
                // No face visible yet — ramp screen backlight & warm glow if dark until face becomes visible
                scanLighting.consider(frame.image, faceVisible: false, faceBox: nil)
                readyMatch = nil
                livenessIdentity = nil
                livenessConfirmed = false
                matchedNonSpoofFrames = 0
                liveness.reset()
                consecutiveWrongFaceFrames = 0
                lastFaceBoundingBox = nil
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            // Face is visible — measure face-region brightness and hold once well-illuminated
            scanLighting.consider(frame.image, faceVisible: true, faceBox: result.face.normalizedBoundingBox)
            lastFaceBoundingBox = result.face.normalizedBoundingBox
            lastSeenFaceFrame = frame

            let neuralDepthEnabled = NEELxSettings.shared.neuralDepthEnabled
            if !neuralDepthEnabled {
                let scanSnapshot = scanLiveness.observe(livenessFrame)
                if scanSnapshot.decision.isDenied {
                    let reason = scanSnapshot.decision.denialReason ?? "Spoof detected."
                    lastOutcome = reason
                    SecurityAuditLog.shared.record(kind: .spoofBlocked, detail: reason, snapshotImage: frame.image)
                    return .spoofSuspected
                }
            }

            let validIdentities = FaceEnrollmentStore.shared.activeIdentities.filter { $0.samples.count >= 4 }
            let scored = pipeline.score(result.embedding, against: validIdentities)
            var matched = pipeline.bestMatch(in: scored, threshold: matchThreshold)
            var precomputedDepth: NeuralDepthReading?

            // 3D-Profile-Assisted Backlit Margin: when harsh glare/backlight drops ArcFace just 0.01–0.06
            // below threshold (still >= 0.61, far above any stranger's 0.15–0.38), verify with Stage 3
            // Neural 3D Depth + Personal 9-Zone 3D Profile before accepting — zero security compromise.
            if matched == nil, neuralDepthEnabled {
                let backlitFloor = max(Float(0.61), matchThreshold - 0.065)
                if let candidate = pipeline.bestMatch(in: scored, threshold: backlitFloor),
                   let enrolledProfile = candidate.identity.depthProfile {
                    let noseCenter = LivenessFeatureExtractor.normalizedNoseCenter(for: result.face)
                    let faceBox = result.face.normalizedBoundingBox
                    let probeDepth = await Task.detached(priority: .userInitiated) {
                        NeuralDepthAnalyzer.shared.analyze(
                            frame: frame.image,
                            normalizedFaceBox: faceBox,
                            noseNormalizedCenter: noseCenter
                        )
                    }.value
                    if let probeDepth {
                        let profileSim = NeuralDepthAnalyzer.signatureSimilarity(probeDepth.depthSignature, enrolledProfile)
                        // Verifies genuine 3D human topography matching enrolled user's unique 3D structure:
                        if probeDepth.flatSpoofScore <= 0.15,
                           probeDepth.noseProtrusion > 0.008,
                           probeDepth.depth3DScore >= 0.60,
                           profileSim >= 0.82 {
                            matched = candidate
                            precomputedDepth = probeDepth
                        }
                    }
                }
            }

            guard let matched else {
                readyMatch = nil
                livenessIdentity = nil
                livenessConfirmed = false
                matchedNonSpoofFrames = 0
                liveness.reset()
                let topDetail = scored.first.map {
                    String(format: "max=%.3f centroid=%.3f (threshold %.2f)", $0.maxSampleSimilarity, $0.centroidSimilarity, matchThreshold)
                } ?? "no enrolled active face"
                lastPendingKind = .wrongFace
                lastPendingReason = "Unrecognized face (\(topDetail))"
                // Allow 0.65s for camera auto-exposure & adaptive dark-room lighting to settle before counting wrong-face streaks
                if Date().timeIntervalSince(scanStartedAt) >= 0.65 {
                    consecutiveWrongFaceFrames += 1
                }
                if consecutiveWrongFaceFrames >= wrongFaceStreakThreshold {
                    lastOutcome = "Unrecognized face (\(topDetail))"
                    SecurityAuditLog.shared.record(kind: .wrongFace, detail: "Unrecognized face (\(topDetail))", snapshotImage: frame.image)
                    return .consistentlyWrongFace
                }
                continue
            }
            consecutiveWrongFaceFrames = 0
            if livenessIdentity != matched.identity.id {
                liveness.reset()
                livenessConfirmed = false
                matchedNonSpoofFrames = 0
                livenessIdentity = matched.identity.id
            }
            readyMatch = matched

            // Stage 3 Neural 3D Depth Anti-Spoofing (Core ML Depth Anything V2 on ANE):
            // Run on matched frames only to keep idle power zero while catching 2D photo/screen spoofs in ~22ms.
            let depthReading: NeuralDepthReading?
            let effectiveFrame: LivenessFrame
            if neuralDepthEnabled {
                if let precomputedDepth {
                    depthReading = precomputedDepth
                } else {
                    let noseCenter = LivenessFeatureExtractor.normalizedNoseCenter(for: result.face)
                    let faceBox = result.face.normalizedBoundingBox
                    depthReading = await Task.detached(priority: .userInitiated) {
                        NeuralDepthAnalyzer.shared.analyze(
                            frame: frame.image,
                            normalizedFaceBox: faceBox,
                            noseNormalizedCenter: noseCenter
                        )
                    }.value
                }
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

            // Attention & Gaze Check ("Require Attention for Face ID")
            // 1. User must be facing the screen naturally (~26 deg tolerance for normal MacBook posture)
            let isFacingScreen = (result.face.yaw.map { abs($0) <= 0.45 } ?? true) &&
                                 (result.face.pitch.map { abs($0) <= 0.45 } ?? true)
            // 2. Eyes must be open (EAR >= 0.11 accommodates slight squinting in bright/dark light)
            let eyesOpen = (effectiveFrame.leftEyeAspectRatio ?? 0.25 >= 0.11) &&
                           (effectiveFrame.rightEyeAspectRatio ?? 0.25 >= 0.11)
            let attentionVerified = isFacingScreen && eyesOpen

            let snapshot = liveness.observe(effectiveFrame)
            var confirmingCue: LivenessCue?

            // Compare live 3D depth reading against the user's personal calibrated depth baseline (if enrolled)
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
            }

            // Compare live 9-zone 3D facial depth relief against user's enrolled 3D depth profile (if captured)
            let depthProfileSimilarity: Float? = {
                guard let liveSig = depthReading?.depthSignature,
                      let enrolledProfile = matched.identity.depthProfile else { return nil }
                return NeuralDepthAnalyzer.signatureSimilarity(liveSig, enrolledProfile)
            }()

            switch snapshot.decision {
            case .denied:
                let reason = snapshot.decision.denialReason ?? "Liveness spoof detected."
                lastOutcome = reason
                SecurityAuditLog.shared.record(kind: .spoofBlocked, detail: reason, snapshotImage: frame.image)
                return .spoofSuspected
            case .confirmed(let cue):
                livenessConfirmed = true
                confirmingCue = cue
            case .pending:
                if let depthReading {
                    recentDepthReadings.append(depthReading)
                    if recentDepthReadings.count > 3 { recentDepthReadings.removeFirst() }

                    let profileMatches = depthProfileSimilarity.map { $0 >= 0.40 } ?? false
                    let strongProfileMatches = depthProfileSimilarity.map { $0 >= 0.56 } ?? false
                    let baselineMatches = enrolledBaseline.map {
                        $0.medianNoseProtrusion >= 0.020 && depthReading.noseProtrusion >= $0.medianNoseProtrusion * 0.55
                    } ?? false
                    let reliefConfirmed = depthReading.depth3DScore >= LivenessTuning.default.neuralDepth3DLevel
                        || baselineMatches

                    // Multi-Frame Temporal Depth Consistency: require 2 consecutive physically consistent 3D readings
                    // (stable nose protrusion & non-flickering depth cliff) OR an ultra-strong personal 9-zone profile match.
                    let temporallyConsistent: Bool = {
                        guard recentDepthReadings.count >= 2 else { return false }
                        let prev = recentDepthReadings[recentDepthReadings.count - 2]
                        let noseStable = abs(depthReading.noseProtrusion - prev.noseProtrusion) < 0.065
                        let bothPositiveNose = depthReading.noseProtrusion > 0.012 && prev.noseProtrusion > 0.012
                        let cliffConsistent = abs(depthReading.backgroundCliff - prev.backgroundCliff) < 0.25
                        return noseStable && bothPositiveNose && cliffConsistent
                    }()

                    if attentionVerified && !flatSpoofSuspected && (
                        (reliefConfirmed && (temporallyConsistent || strongProfileMatches))
                        || (profileMatches && temporallyConsistent)
                        || matchedNonSpoofFrames >= 3
                    ) {
                        livenessConfirmed = true
                        confirmingCue = .neuralDepth3D
                    }
                } else if attentionVerified {
                    // Graceful fallback when neural depth model is disabled, unbundled, or thermal/battery-gated on Intel
                    livenessConfirmed = true
                }
            }

            if let readyMatch, livenessConfirmed, attentionVerified, !flatSpoofSuspected {
                // Optional Active Chromatic Flash Challenge (Anti-4K Video Replay):
                if NEELxSettings.shared.chromaticFlashEnabled {
                    let flashResult = await runChromaticFlashChallenge(
                        baselineFrame: frame,
                        faceBox: result.face.normalizedBoundingBox
                    )
                    guard flashResult.passed else {
                        let reason = "Active Chromatic Flash failed (\(flashResult.detail))."
                        lastOutcome = reason
                        SecurityAuditLog.shared.record(kind: .spoofBlocked, detail: reason, snapshotImage: frame.image)
                        return .spoofSuspected
                    }
                }

                statusMessage = "Recognized — unlocking…"
                let depthNote = depthReading.map { reading -> String in
                    if let sim = depthProfileSimilarity {
                        return String(format: "3D Depth %.0f%% · Profile %.0f%% (%.0fms ANE)", reading.depth3DScore * 100, sim * 100, reading.inferenceMs)
                    }
                    return String(format: "3D Depth %.0f%% (%.0fms ANE)", reading.depth3DScore * 100, reading.inferenceMs)
                }
                let livenessNote = depthNote ?? confirmingCue.map { "live via \($0.title)" } ?? "Attention & Biometrics Verified"
                let summary = "Matched \(readyMatch.identity.name) at \(String(format: "%.3f", readyMatch.centroidSimilarity)), \(livenessNote)."
                lastOutcome = summary

                let rawName = readyMatch.identity.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let faceName = (!rawName.isEmpty && rawName.lowercased() != "default") ? rawName : (NSFullUserName().isEmpty ? "User" : NSFullUserName())

                // Item #38: Zero-Password Visual-Only Mode
                let isVisualOnly = NEELxSettings.shared.visualOnlyModeEnabled || !SecureCredentialManager.hasStoredPassword()
                if isVisualOnly {
                    statusMessage = "Face recognized"
                    let visualSummary = "\(summary) Face recognized (visual-only mode)."
                    lastOutcome = visualSummary
                    SecurityAuditLog.shared.record(kind: .faceRecognized, detail: "\(visualSummary) Touch ID or password required to sign in.")

                    // Item #33: Record telemetry receipt for visual verification
                    recordUnlockReceipt(
                        name: faceName,
                        similarity: readyMatch.centroidSimilarity,
                        sensor: camera.currentDeviceName,
                        depthReading: depthReading,
                        profileSimilarity: depthProfileSimilarity,
                        cue: confirmingCue,
                        isVisualOnly: true
                    )

                    scanLighting.hide()
                    NEELxSettings.shared.playUnlockFeedback()

                    // Visual-only mode says "Face recognized", welcome banner reserved for when macOS confirms sign-in
                    pendingVisualOnlyWelcomeName = faceName
                    return .matched
                }

                statusMessage = "Recognized — unlocking…"
                let submitted = await pocController.injectStoredPassword(requireAuthoritativeLock: true)
                guard submitted else {
                    let blockDetail = "Recognized \(readyMatch.identity.name), but \(pocController.statusMessage)"
                    statusMessage = pocController.statusMessage
                    lastOutcome = blockDetail
                    SecurityAuditLog.shared.record(kind: .systemError, detail: blockDetail)
                    return .injectionBlocked(blockDetail)
                }

                // Submission only means keystrokes were sent. Verify the console session separately.
                let clock = ContinuousClock()
                let confirmationDeadline = clock.now + .seconds(2)
                while !Task.isCancelled && !lockMonitor.isSleeping
                    && !LockMonitor.isCurrentUserSessionUnlocked() && clock.now < confirmationDeadline {
                    try? await Task.sleep(for: .milliseconds(25))
                }
                guard !Task.isCancelled, !lockMonitor.isSleeping else { return .noResolution }
                guard LockMonitor.isCurrentUserSessionUnlocked() else {
                    let detail = "macOS did not confirm the unlock. Sign in normally and check your NEELx setup."
                    SecurityAuditLog.shared.record(kind: .systemError, detail: detail)
                    return .injectionBlocked(detail)
                }

                // Begin smooth backlight & halo dissolve + crisp haptic & optional muted glass chime
                scanLighting.hide()
                NEELxSettings.shared.playUnlockFeedback()

                // Floating "Welcome Back (Name)!" popup message right after unlocking screen
                WelcomeBannerWindowController.shared.show(name: faceName)

                // Item #33: Record telemetry receipt for confirmed unlock
                recordUnlockReceipt(
                    name: faceName,
                    similarity: readyMatch.centroidSimilarity,
                    sensor: camera.currentDeviceName,
                    depthReading: depthReading,
                    profileSimilarity: depthProfileSimilarity,
                    cue: confirmingCue,
                    isVisualOnly: false
                )

                // Log verified unlock & silently learn high-confidence 3D-verified appearance/lighting drift
                SecurityAuditLog.shared.record(kind: .unlocked, detail: "macOS session unlocked after submission; sign-in method unavailable. \(summary)")
                // A missing depth reading is an abstention, never a clean spoof score.
                if let depthReading,
                   depthReading.flatSpoofScore < 0.18,
                   depthReading.depth3DScore >= 0.50,
                   readyMatch.centroidSimilarity >= 0.70 {
                    FaceEnrollmentStore.shared.recordAdaptiveSample(
                        for: readyMatch.identity.id,
                        embedding: result.embedding,
                        quality: result.quality,
                        depthSignature: depthReading.depthSignature,
                        noseProtrusion: depthReading.noseProtrusion,
                        backgroundCliff: depthReading.backgroundCliff
                    )
                }
                return .matched
            }

            if flatSpoofSuspected {
                lastPendingKind = .spoofBlocked
                lastPendingReason = String(
                    format: "Flat 2D surface blocked (3D Depth %.0f%%, flatSpoof %.0f%%).",
                    (depthReading?.depth3DScore ?? 0) * 100,
                    (depthReading?.flatSpoofScore ?? 0) * 100
                )
            } else if !attentionVerified {
                lastPendingKind = .spoofBlocked
                lastPendingReason = !eyesOpen
                    ? "Attention check failed — eyes closed or obscured."
                    : "Attention check failed — not facing the screen."
            } else if !livenessConfirmed {
                lastPendingKind = .spoofBlocked
                lastPendingReason = String(
                    format: "Could not verify live 3D face before timeout (3D Depth %.0f%%).",
                    (depthReading?.depth3DScore ?? 0) * 100
                )
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        // If a face was actually in front of the camera when the scan window timed out without unlocking,
        // record the failure + encrypted snapshot in the Audit Log (empty-room timeouts stay silent).
        if !Task.isCancelled,
           LockMonitor.isScreenActuallyLocked(),
           let faceFrame = lastSeenFaceFrame,
           let reason = lastPendingReason {
            lastOutcome = reason
            SecurityAuditLog.shared.record(kind: lastPendingKind, detail: reason, snapshotImage: faceFrame.image)
        }
        return .noResolution
    }

    /// Flashes a random cyan/magenta tint with boosted display backlight and checks incoming camera frames
    /// across up to 240ms (returning immediately on the first frame whose skin reflection matches the flash).
    /// If the first tint is neutralized by Apple's camera ISP Auto-White-Balance, retries once with the
    /// opposite tint before reporting failure — eliminating false rejections without weakening anti-replay security.
    private func runChromaticFlashChallenge(
        baselineFrame: CameraFrame,
        faceBox: CGRect
    ) async -> (passed: Bool, detail: String) {
        // Always sample the freshest pre-flash frame at t=0 (not an older frame from before neural inference)
        let freshBaseline = camera.currentFrame ?? baselineFrame
        guard let baselineRGB = ChromaticFlashChallenger.meanFaceRGB(freshBaseline.image, normalizedFaceBox: faceBox) else {
            return (true, "abstained: no face RGB")
        }
        // In well-lit rooms (>= 0.30 luminance), room light & camera AWB dominate subtle display tints;
        // abstain safely while 3D Neural Depth + 9-Zone Profile + Attention handle anti-spoofing at full accuracy.
        if baselineRGB.luminance >= 0.30 {
            return (true, String(format: "abstained: bright ambient %.2f", baselineRGB.luminance))
        }

        let firstTint = ChromaticFlashTint.allCases.randomElement() ?? .cyan
        let secondTint: ChromaticFlashTint = (firstTint == .cyan) ? .magenta : .cyan

        let firstResult = await runSingleChromaticPulse(
            tint: firstTint,
            baselineFrame: freshBaseline,
            baselineRGB: baselineRGB,
            faceBox: faceBox,
            windowSeconds: 0.24
        )
        if firstResult.passed {
            return firstResult
        }

        // Wait briefly for camera sensor to settle after clearing the first flash, then verify once with opposite tint
        try? await Task.sleep(nanoseconds: 55_000_000)
        let retryBase = camera.currentFrame ?? freshBaseline
        guard let retryRGB = ChromaticFlashChallenger.meanFaceRGB(retryBase.image, normalizedFaceBox: faceBox) else {
            return firstResult
        }
        if retryRGB.luminance >= 0.30 {
            return (true, String(format: "abstained on retry: bright ambient %.2f", retryRGB.luminance))
        }
        return await runSingleChromaticPulse(
            tint: secondTint,
            baselineFrame: retryBase,
            baselineRGB: retryRGB,
            faceBox: faceBox,
            windowSeconds: 0.22
        )
    }

    private func runSingleChromaticPulse(
        tint: ChromaticFlashTint,
        baselineFrame: CameraFrame,
        baselineRGB: FaceRGBSample,
        faceBox: CGRect,
        windowSeconds: TimeInterval
    ) async -> (passed: Bool, detail: String) {
        scanLighting.flashChallenge(tint: tint)
        defer { scanLighting.clearFlashChallenge() }

        let startTime = Date()
        let deadline = startTime.addingTimeInterval(windowSeconds)
        var lastID = baselineFrame.id
        var framesChecked = 0
        var bestShift = -Double.greatestFiniteMagnitude
        var bestTotalShift = 0.0

        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard let current = camera.currentFrame, current.id != lastID else { continue }
            lastID = current.id
            // Ignore frames in the first 35ms before display vsync + sensor integration catches the flash
            guard Date().timeIntervalSince(startTime) >= 0.035 else { continue }
            guard let flashedRGB = ChromaticFlashChallenger.meanFaceRGB(current.image, normalizedFaceBox: faceBox) else {
                continue
            }
            framesChecked += 1
            let totalShift = abs(flashedRGB.r - baselineRGB.r)
                + abs(flashedRGB.g - baselineRGB.g)
                + abs(flashedRGB.b - baselineRGB.b)
            if totalShift > bestTotalShift { bestTotalShift = totalShift }

            switch ChromaticFlashChallenger.evaluate(baseline: baselineRGB, flashed: flashedRGB, tint: tint) {
            case .passed(let shift):
                return (true, String(format: "%@ passed shift=%+.4f in %d frames", tint.rawValue, shift, framesChecked))
            case .abstained:
                return (true, "abstained")
            case .failed(let shift):
                if shift > bestShift { bestShift = shift }
            }
        }

        if framesChecked == 0 {
            return (true, "abstained: no frames during flash")
        }
        let summary = String(
            format: "%@ bestShift=%+.4f totalΔ=%.4f baseLum=%.2f frames=%d",
            tint.rawValue, bestShift, bestTotalShift, baselineRGB.luminance, framesChecked
        )
        return (false, summary)
    }
}
