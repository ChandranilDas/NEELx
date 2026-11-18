//
//  PresenceAutoLocker.swift
//  NEELx
//
//  Optional Walk-Away Auto-Lock ("Presence Lock").
//  Zero continuous camera drain: only wakes the camera for ~0.8s AFTER keyboard/mouse
//  idle exceeds the user's configured delay. If you're reading or watching at your desk
//  it stays unlocked; if you stepped away, it immediately locks your Mac via SACLockScreenImmediate.
//

import CoreGraphics
import Foundation

@MainActor
final class PresenceAutoLocker {
    private var timer: Timer?
    private var isChecking = false
    private var lastCheckAt: Date = .distantPast
    private let recheckCooldown: TimeInterval = 15

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.tick()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func tick() async {
        let settings = NEELxSettings.shared
        guard settings.presenceAutoLockEnabled,
              !isChecking,
              !LockMonitor.isScreenActuallyLocked() else { return }

        let now = Date()
        guard now.timeIntervalSince(lastCheckAt) >= recheckCooldown else { return }

        let anyInput = CGEventType(rawValue: ~0)!
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInput
        )
        let threshold = TimeInterval(settings.presenceAutoLockSeconds)
        guard idleSeconds >= threshold else { return }

        isChecking = true
        lastCheckAt = now
        defer { isChecking = false }

        let camera = CameraManager()
        await camera.start()
        defer { camera.stop() }
        guard camera.errorMessage == nil else { return }

        // Check up to 4 frames (~0.8s total) to let auto-exposure settle and avoid false locks
        var personPresent = false
        var lastID: UInt64?
        let deadline = Date().addingTimeInterval(0.9)
        while Date() < deadline {
            if LockMonitor.isScreenActuallyLocked() { return }
            // If the user touched the keyboard or mouse while checking, abort immediately
            let currentIdle = CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: anyInput
            )
            if currentIdle < 2.0 {
                personPresent = true
                break
            }
            if let frame = camera.currentFrame, frame.id != lastID {
                lastID = frame.id
                let image = frame.image
                let foundFace = await Task.detached(priority: .utility) {
                    (try? FaceDetector.detectFaces(in: image).isEmpty == false) ?? false
                }.value
                if foundFace {
                    personPresent = true
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        if !personPresent, !LockMonitor.isScreenActuallyLocked() {
            Self.lockScreenImmediately()
        }
    }

    /// Invokes macOS's native `SACLockScreenImmediate` from `login.framework` (instant, clean lock screen).
    private static func lockScreenImmediately() {
        typealias LockFn = @convention(c) () -> Void
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_LAZY),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            let lock = unsafeBitCast(sym, to: LockFn.self)
            lock()
        }
    }
}
