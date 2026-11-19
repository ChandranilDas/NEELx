//
//  NEELxSettings.swift
//  NEELx
//
//  Backed directly by `UserDefaults.standard` — each property's `didSet`
//  writes through immediately, so there's no explicit "save" step.
//

import AppKit
import Foundation
import Observation

/// How long the Touch-ID-unlocked session may sit idle before it re-locks.
enum AutoLockInterval: Int, CaseIterable, Identifiable {
    case oneDay = 1
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30

    var id: Int { rawValue }

    var title: String { rawValue == 1 ? "1 day" : "\(rawValue) days" }

    var duration: TimeInterval { TimeInterval(rawValue) * 24 * 60 * 60 }

    /// Position in `allCases`, used to drive the discrete 4-stop slider.
    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> AutoLockInterval {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .sevenDays
    }
}

/// Unlock success/failure animation style shown in the notch overlay.
enum UnlockAnimationStyle: String, CaseIterable, Identifiable {
    case none
    case minimal
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .minimal: return "Minimal"
        case .original: return "Original"
        }
    }

    /// The styles the picker offers; `.none` is still a valid stored value but is now produced by the "Show animation" toggle, not a tile.
    static let selectableCases: [UnlockAnimationStyle] = [.minimal, .original]
}

/// What can prompt Face Unlock. Multi-select; at least one is always kept
/// selected, since a Mac with none armed would never show the notch.
enum UnlockTrigger: String, CaseIterable, Identifiable {
    /// The display turned back on (see `LockEventKind.wake`).
    case onWake
    /// The screen just became locked, no wake involved.
    case onLock
    /// Pressing space on the lock screen starts a scan. The lock screen's
    /// Secure Event Input blocks normal event taps, so this is detected via
    /// IOKit HID instead (see `SpaceKeyMonitor`), requiring Input Monitoring.
    case onSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onWake: return "On wake"
        case .onLock: return "On lock"
        case .onSpace: return "On key"
        }
    }

    var iconName: String {
        switch self {
        case .onWake: return "moon.fill"
        case .onLock: return "lock.laptopcomputer"
        case .onSpace: return "keyboard"
        }
    }
}

@Observable
@MainActor
final class NEELxSettings {
    static let shared = NEELxSettings()

    private enum Key {
        static let isFaceUnlockEnabled = "NEELxSettings.isFaceUnlockEnabled"
        static let matchThreshold = "NEELxSettings.matchThreshold"
        static let livenessChecksEnabled = "NEELxSettings.livenessChecksEnabled"
        static let livenessMode = "NEELxSettings.livenessMode"
        static let neuralDepthEnabled = "NEELxSettings.neuralDepthEnabled"
        static let chromaticFlashEnabled = "NEELxSettings.chromaticFlashEnabled"
        static let intruderLogEnabled = "NEELxSettings.intruderLogEnabled"
        static let adaptiveLearningEnabled = "NEELxSettings.adaptiveLearningEnabled"
        static let systemAuthPromptsEnabled = "NEELxSettings.systemAuthPromptsEnabled"
        static let presenceAutoLockEnabled = "NEELxSettings.presenceAutoLockEnabled"
        static let presenceAutoLockSeconds = "NEELxSettings.presenceAutoLockSeconds"
        static let minimumFaceWidth = "NEELxSettings.minimumFaceWidth"
        static let unlockAnimationStyle = "NEELxSettings.unlockAnimationStyle"
        static let showUnlockAnimation = "NEELxSettings.showUnlockAnimation"
        /// Legacy bool key — read once during migration, then ignored.
        static let playUnlockAnimation = "NEELxSettings.playUnlockAnimation"
        static let unlockTriggers = "NEELxSettings.unlockTriggers"
        static let retryOnHover = "NEELxSettings.retryOnHover"
        static let faceDetectionSeconds = "NEELxSettings.faceDetectionSeconds"
        static let autoRetryOnce = "NEELxSettings.autoRetryOnce"
        static let hapticFeedbackEnabled = "NEELxSettings.hapticFeedbackEnabled"
        static let unlockSoundEnabled = "NEELxSettings.unlockSoundEnabled"
        static let preferredDisplayID = "NEELxSettings.preferredDisplayID"
        static let preferredDisplayName = "NEELxSettings.preferredDisplayName"
        static let autoLockIntervalDays = "NEELxSettings.autoLockIntervalDays"
        static let defaultCameraID = "NEELxSettings.defaultCameraID"
        static let builtInDisplayCameraID = "NEELxSettings.builtInDisplayCameraID"
        static let externalDisplayCameraID = "NEELxSettings.externalDisplayCameraID"
        static let allowContinuityCamera = "NEELxSettings.allowContinuityCamera"
        static let dualCameraConcurrentUnlock = "NEELxSettings.dualCameraConcurrentUnlock"
        static let deviceProximityGuardEnabled = "NEELxSettings.deviceProximityGuardEnabled"
        static let hasCompletedOnboarding = "NEELxSettings.hasCompletedOnboarding"
        static let onboardingResumeStep = "NEELxSettings.onboardingResumeStep"
        static let hasAcknowledgedSecurityNotice = "NEELxSettings.hasAcknowledgedSecurityNotice"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    var isFaceUnlockEnabled: Bool {
        didSet { defaults.set(isFaceUnlockEnabled, forKey: Key.isFaceUnlockEnabled) }
    }
    var matchThreshold: Float {
        didSet { defaults.set(matchThreshold, forKey: Key.matchThreshold) }
    }
    /// Master switch for liveness checking. Off means face recognition
    /// alone decides an unlock — a photo of the enrolled user would pass.
    var livenessChecksEnabled: Bool {
        didSet { defaults.set(livenessChecksEnabled, forKey: Key.livenessChecksEnabled) }
    }
    /// Light (deny-only) vs Heavy (deny plus a required proof of life) —
    /// see `LivenessMode`.
    var livenessMode: LivenessMode {
        didSet { defaults.set(livenessMode.rawValue, forKey: Key.livenessMode) }
    }
    /// Stage 3 Core ML Depth Anything V2 3D anti-spoofing on Apple Silicon ANE.
    /// Hardcoded Always ON — critical for biometric security against photo & video replay.
    var neuralDepthEnabled: Bool {
        get { true }
        set { defaults.set(true, forKey: Key.neuralDepthEnabled) }
    }
    /// Whether NEELx can automatically discover and use a nearby iPhone or iPad Pro camera.
    /// Kept OFF by default so user explores options and enables explicitly.
    var allowContinuityCamera: Bool {
        didSet {
            defaults.set(allowContinuityCamera, forKey: Key.allowContinuityCamera)
            ContinuityDeviceVerifier.shared.refresh()
        }
    }
    /// Whether NEELx polls both the Mac camera and iPhone/iPad camera concurrently for unlock.
    /// Kept OFF by default.
    var dualCameraConcurrentUnlock: Bool {
        didSet { defaults.set(dualCameraConcurrentUnlock, forKey: Key.dualCameraConcurrentUnlock) }
    }
    /// Whether unlock requires the paired iPhone/iPad to be within close Bluetooth LE proximity (< 1.5m).
    /// Kept OFF by default.
    var deviceProximityGuardEnabled: Bool {
        didSet {
            defaults.set(deviceProximityGuardEnabled, forKey: Key.deviceProximityGuardEnabled)
            DeviceProximityGuard.shared.updateState()
        }
    }
    /// Active Chromatic Flash Challenge to defeat 4K video replay attacks.
    var chromaticFlashEnabled: Bool {
        didSet { defaults.set(chromaticFlashEnabled, forKey: Key.chromaticFlashEnabled) }
    }
    /// Encrypted local audit log for unlock and blocked intruder/spoof events.
    var intruderLogEnabled: Bool {
        didSet { defaults.set(intruderLogEnabled, forKey: Key.intruderLogEnabled) }
    }
    /// Silently learns high-confidence verified appearances (glasses, beard, lighting drift).
    var adaptiveLearningEnabled: Bool {
        didSet { defaults.set(adaptiveLearningEnabled, forKey: Key.adaptiveLearningEnabled) }
    }
    /// iPhone/iPad Pro-style Face ID for macOS system Touch ID & admin password dialogs
    /// (app installs, System Settings, Saved Passwords, Keychain).
    var systemAuthPromptsEnabled: Bool {
        didSet { defaults.set(systemAuthPromptsEnabled, forKey: Key.systemAuthPromptsEnabled) }
    }
    /// Walk-Away Auto-Lock ("Presence Lock") when user steps away from the desk.
    var presenceAutoLockEnabled: Bool {
        didSet { defaults.set(presenceAutoLockEnabled, forKey: Key.presenceAutoLockEnabled) }
    }
    var presenceAutoLockSeconds: Int {
        didSet { defaults.set(presenceAutoLockSeconds, forKey: Key.presenceAutoLockSeconds) }
    }
    /// Mirrored into `FaceRecognitionPipeline.minimumProminentFaceWidth` on
    /// every change, since that's read from a background `nonisolated` context.
    var minimumFaceWidth: Float {
        didSet {
            defaults.set(minimumFaceWidth, forKey: Key.minimumFaceWidth)
            FaceRecognitionPipeline.minimumProminentFaceWidth = minimumFaceWidth
        }
    }
    /// The remembered choice (`.minimal`/`.original` only); `showUnlockAnimation`
    /// tracks on/off separately so toggling back on restores the prior pick.
    /// Read `effectiveUnlockAnimationStyle`, not this, to decide what to show.
    var unlockAnimationStyle: UnlockAnimationStyle {
        didSet { defaults.set(unlockAnimationStyle.rawValue, forKey: Key.unlockAnimationStyle) }
    }
    var showUnlockAnimation: Bool {
        didSet { defaults.set(showUnlockAnimation, forKey: Key.showUnlockAnimation) }
    }

    /// What the overlay should actually render — the pick, or `.none` when
    /// animations are switched off entirely.
    var effectiveUnlockAnimationStyle: UnlockAnimationStyle {
        showUnlockAnimation ? unlockAnimationStyle : .none
    }

    /// Which signals arm Face Unlock. Persisted as raw-value strings; the
    /// setter refuses to store an empty set (see `UnlockTrigger`).
    var unlockTriggers: Set<UnlockTrigger> {
        didSet {
            // Belt-and-braces behind the picker's own min-one rule. This
            // reassignment re-enters didSet once, then terminates since the
            // corrected value is never itself empty.
            if unlockTriggers.isEmpty {
                unlockTriggers = oldValue.isEmpty ? Set(UnlockTrigger.allCases) : oldValue
            }
            defaults.set(unlockTriggers.map(\.rawValue), forKey: Key.unlockTriggers)
        }
    }
    var retryOnHover: Bool {
        didSet { defaults.set(retryOnHover, forKey: Key.retryOnHover) }
    }
    /// How long each scan cycle looks for a face before giving up. Must stay
    /// equal to `FaceUnlockCoordinator.scanWindowDuration` and
    /// `NotchOverlayController.scanTimeoutDuration`.
    var faceDetectionSeconds: Int {
        didSet {
            // Only reassign when clamping actually changes the value —
            // unconditional reassignment would recurse infinitely, since the
            // slider only ever produces already-in-range values.
            let clamped = min(max(faceDetectionSeconds, Self.faceDetectionRange.lowerBound),
                               Self.faceDetectionRange.upperBound)
            guard clamped == faceDetectionSeconds else {
                faceDetectionSeconds = clamped
                return
            }
            defaults.set(faceDetectionSeconds, forKey: Key.faceDetectionSeconds)
        }
    }
    var autoRetryOnce: Bool {
        didSet { defaults.set(autoRetryOnce, forKey: Key.autoRetryOnce) }
    }
    /// Trackpad haptic on hovering the notch/pill and on a successful unlock —
    /// see `NotchOverlayView`'s hover handler and `.onChange(of: controller.phase)`.
    var hapticFeedbackEnabled: Bool {
        didSet { defaults.set(hapticFeedbackEnabled, forKey: Key.hapticFeedbackEnabled) }
    }

    static let faceDetectionRange = 3...10

    /// Which display Face Unlock shows on. `nil` means `NotchGeometry.preferredScreen()`'s
    /// default, re-evaluated live; a pinned display has deliberately no
    /// fallback if disconnected (see `FaceUnlockCoordinator.evaluateTrigger()`).
    var preferredDisplayID: String? {
        didSet { defaults.set(preferredDisplayID, forKey: Key.preferredDisplayID) }
    }
    /// The chosen display's name at pick time — cosmetic only, so the row can
    /// show something recognizable when that display is disconnected.
    var preferredDisplayName: String? {
        didSet { defaults.set(preferredDisplayName, forKey: Key.preferredDisplayName) }
    }
    /// Enforced by `SessionAutoLocker`, not here — this is only the stored
    /// preference.
    var autoLockInterval: AutoLockInterval {
        didSet { defaults.set(autoLockInterval.rawValue, forKey: Key.autoLockIntervalDays) }
    }
    /// Device `uniqueID`s, not device objects — devices can disconnect/
    /// reconnect between launches, but their unique ID is stable.
    var defaultCameraID: String? {
        didSet { defaults.set(defaultCameraID, forKey: Key.defaultCameraID) }
    }
    var builtInDisplayCameraID: String? {
        didSet { defaults.set(builtInDisplayCameraID, forKey: Key.builtInDisplayCameraID) }
    }
    var externalDisplayCameraID: String? {
        didSet { defaults.set(externalDisplayCameraID, forKey: Key.externalDisplayCameraID) }
    }

    /// Gates first-run onboarding — `AppDelegate` shows it instead of the
    /// Settings window until this is `true`. Set once, by `OnboardingController`
    /// on the true first-run flow reaching `.complete`.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }
    /// Where to resume first-run onboarding if the app quit mid-flow; `nil`
    /// starts fresh at `.intro`. Steps depending on in-memory capture state
    /// collapse to `.preSetup` before storing, since that state doesn't
    /// survive a relaunch — see `OnboardingStep.resumeTarget`.
    var onboardingResumeStep: OnboardingStep? {
        didSet { defaults.set(onboardingResumeStep?.rawValue, forKey: Key.onboardingResumeStep) }
    }
    /// Gates the one-time post-update notice for users who completed onboarding before the
    /// security-disclaimer step existed. Set alongside `hasCompletedOnboarding` for anyone
    /// finishing normal onboarding (which now includes that step), and separately by
    /// `OnboardingController.startPostUpdateNotice()` once the standalone catch-up notice is
    /// acknowledged. Defaults `false`, so an upgrading 1.0 install (where this key has never
    /// been written) correctly triggers the catch-up flow once.
    var hasAcknowledgedSecurityNotice: Bool {
        didSet { defaults.set(hasAcknowledgedSecurityNotice, forKey: Key.hasAcknowledgedSecurityNotice) }
    }

    private init() {
        // Enabled by default — onboarding already enrolled a face and set a
        // password specifically to use Face Unlock.
        isFaceUnlockEnabled = defaults.object(forKey: Key.isFaceUnlockEnabled) as? Bool ?? true
        // Matches `MatchConfidenceLevel.standard` — see RecognitionSettingsPage.swift.
        matchThreshold = defaults.object(forKey: Key.matchThreshold) as? Float ?? 0.63
        livenessChecksEnabled = defaults.object(forKey: Key.livenessChecksEnabled) as? Bool ?? true
        // Light by default — with Attention & Gaze verification, user presence is verified instantly
        // while anti-spoofing cues (glare, bezel detection) catch photos or screens.
        livenessMode = defaults.string(forKey: Key.livenessMode)
            .flatMap(LivenessMode.init(rawValue:)) ?? .light
        chromaticFlashEnabled = defaults.object(forKey: Key.chromaticFlashEnabled) as? Bool ?? false
        intruderLogEnabled = defaults.object(forKey: Key.intruderLogEnabled) as? Bool ?? true
        adaptiveLearningEnabled = defaults.object(forKey: Key.adaptiveLearningEnabled) as? Bool ?? true
        systemAuthPromptsEnabled = defaults.object(forKey: Key.systemAuthPromptsEnabled) as? Bool ?? true
        presenceAutoLockEnabled = defaults.object(forKey: Key.presenceAutoLockEnabled) as? Bool ?? false
        allowContinuityCamera = defaults.bool(forKey: Key.allowContinuityCamera)
        dualCameraConcurrentUnlock = defaults.bool(forKey: Key.dualCameraConcurrentUnlock)
        deviceProximityGuardEnabled = defaults.bool(forKey: Key.deviceProximityGuardEnabled)
        let storedPresenceDelay = defaults.object(forKey: Key.presenceAutoLockSeconds) as? Int ?? 60
        presenceAutoLockSeconds = [30, 60, 120, 300].contains(storedPresenceDelay) ? storedPresenceDelay : 60
        // Matches `DetectionDistanceLevel.standard` — see RecognitionSettingsPage.swift.
        minimumFaceWidth = defaults.object(forKey: Key.minimumFaceWidth) as? Float ?? 0.19

        // Resolve the stored style first, `.none` included, then split it
        // into the pick + the on/off flag the UI now works in.
        let storedStyle: UnlockAnimationStyle
        if let raw = defaults.string(forKey: Key.unlockAnimationStyle),
           let style = UnlockAnimationStyle(rawValue: raw) {
            storedStyle = style
        } else if let legacy = defaults.object(forKey: Key.playUnlockAnimation) as? Bool {
            // Migrate the oldest on/off toggle: off → none, on → original.
            storedStyle = legacy ? .original : .none
        } else {
            storedStyle = .original
        }
        // A stored `.none` becomes "off, remembering .original" so
        // switching back on has something to restore.
        unlockAnimationStyle = storedStyle == .none ? .original : storedStyle
        showUnlockAnimation = defaults.object(forKey: Key.showUnlockAnimation) as? Bool
            ?? (storedStyle != .none)

        // On wake/lock by default, not on space — `.onSpace` needs Input
        // Monitoring, which a fresh install shouldn't request unprompted.
        let storedTriggers = (defaults.array(forKey: Key.unlockTriggers) as? [String])?
            .compactMap { raw -> UnlockTrigger? in
                // "onActivity" was merged into "onWake"; keep old installs working.
                if raw == "onActivity" { return .onWake }
                return UnlockTrigger(rawValue: raw)
            }
        unlockTriggers = storedTriggers.map(Set.init).flatMap { $0.isEmpty ? nil : $0 }
            ?? [.onWake, .onLock]
        // One-time migration from the experimental manual Space trigger.
        if !defaults.bool(forKey: "NEELx.wakeMigration1") {
            unlockTriggers = [.onWake, .onLock]
            minimumFaceWidth = 0.15
            defaults.set(["onWake", "onLock"], forKey: Key.unlockTriggers)
            defaults.set(Float(0.15), forKey: Key.minimumFaceWidth)
            defaults.set(true, forKey: "NEELx.wakeMigration1")
        }
        retryOnHover = defaults.object(forKey: Key.retryOnHover) as? Bool ?? false
        faceDetectionSeconds = (defaults.object(forKey: Key.faceDetectionSeconds) as? Int)
            .map { min(max($0, Self.faceDetectionRange.lowerBound), Self.faceDetectionRange.upperBound) }
            ?? 5
        autoRetryOnce = defaults.object(forKey: Key.autoRetryOnce) as? Bool ?? false
        hapticFeedbackEnabled = defaults.object(forKey: Key.hapticFeedbackEnabled) as? Bool ?? true
        unlockSoundEnabled = defaults.object(forKey: Key.unlockSoundEnabled) as? Bool ?? false
        preferredDisplayID = defaults.string(forKey: Key.preferredDisplayID)
        preferredDisplayName = defaults.string(forKey: Key.preferredDisplayName)

        // Defaults to 7 days — long enough not to nag daily users, short
        // enough not to leave an abandoned session live indefinitely.
        autoLockInterval = (defaults.object(forKey: Key.autoLockIntervalDays) as? Int)
            .flatMap(AutoLockInterval.init(rawValue:)) ?? .sevenDays
        defaultCameraID = defaults.string(forKey: Key.defaultCameraID)
        builtInDisplayCameraID = defaults.string(forKey: Key.builtInDisplayCameraID)
        externalDisplayCameraID = defaults.string(forKey: Key.externalDisplayCameraID)
        hasCompletedOnboarding = defaults.object(forKey: Key.hasCompletedOnboarding) as? Bool ?? false
        onboardingResumeStep = defaults.string(forKey: Key.onboardingResumeStep)
            .flatMap(OnboardingStep.init(rawValue:))
        hasAcknowledgedSecurityNotice = defaults.object(forKey: Key.hasAcknowledgedSecurityNotice) as? Bool ?? false

        // Push into the nonisolated mirror immediately, or FaceRecognitionPipeline
        // would keep its own default until the slider is first touched.
        FaceRecognitionPipeline.minimumProminentFaceWidth = minimumFaceWidth
    }

    /// Optional muted Apple-style soft glass sound cue timed with the green Face ID checkmark (off by default).
    var unlockSoundEnabled: Bool {
        didSet { defaults.set(unlockSoundEnabled, forKey: Key.unlockSoundEnabled) }
    }

    /// Plays spatial Trackpad haptic tap + optional soft muted glass chime synchronized with the unlock checkmark.
    func playUnlockFeedback() {
        if hapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if unlockSoundEnabled {
            if let sound = NSSound(named: NSSound.Name("Glass")) {
                sound.volume = 0.22
                sound.play()
            }
        }
    }

    /// Wipes all stored credentials, enrolled face profiles, and resets all settings to fresh out-of-the-box defaults.
    func resetToFactoryDefaults() {
        SecureCredentialManager.resetAllState()
        FaceEnrollmentStore.shared.deleteAll()
        if let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
        }
        defaults.synchronize()

        // Reset runtime properties to clean defaults
        isFaceUnlockEnabled = true
        matchThreshold = 0.63
        livenessChecksEnabled = true
        livenessMode = .light
        chromaticFlashEnabled = false
        intruderLogEnabled = true
        adaptiveLearningEnabled = true
        systemAuthPromptsEnabled = true
        presenceAutoLockEnabled = false
        allowContinuityCamera = false
        dualCameraConcurrentUnlock = false
        deviceProximityGuardEnabled = false
        presenceAutoLockSeconds = 60
        minimumFaceWidth = 0.19
        unlockAnimationStyle = .original
        showUnlockAnimation = true
        unlockTriggers = [.onWake, .onLock]
        retryOnHover = false
        faceDetectionSeconds = 5
        autoRetryOnce = false
        hapticFeedbackEnabled = true
        unlockSoundEnabled = false
        preferredDisplayID = nil
        preferredDisplayName = nil
        autoLockInterval = .sevenDays
        defaultCameraID = nil
        builtInDisplayCameraID = nil
        externalDisplayCameraID = nil
        hasCompletedOnboarding = false
        onboardingResumeStep = nil
        hasAcknowledgedSecurityNotice = false
        FaceRecognitionPipeline.minimumProminentFaceWidth = minimumFaceWidth
    }
}
