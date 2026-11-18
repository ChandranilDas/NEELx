//
//  ScanLightingController.swift
//  NEELx
//
//  Cinema-smooth adaptive low-light illumination for both lock-screen verification and
//  guided face enrollment. Uses 60fps cubic-eased hardware display backlight transitions
//  (via DisplayServices) paired with a softly feathered TrueTone ambient halo (zero harsh
//  edges or abrupt snaps) that smoothly breathes up in dark rooms and gently dissolves
//  back to your exact original screen brightness once verification completes.
//

import AppKit
import CoreGraphics
import Foundation
import QuartzCore

/// Visibility aid only: illumination is never treated as proof of liveness.
@MainActor
final class ScanLightingController {
    private var panel: NotchWindow?
    private var lightView: ScanLightHaloView?
    private var delegated = false

    private var isActive = false
    private var forEnrollment = false
    private var allowWhenUnlocked = false
    private var savedBrightness: Float?
    private var currentHardwareBrightness: Float?
    private var currentBoostLevel: Double = 0 // 0.0 (off) ... 1.0 (max dark-room boost)
    private var lastAdjustmentAt: CFAbsoluteTime = 0

    /// Shared preview controller so the user can admire the Studio Light & spectral rim directly from Settings.
    private static let previewController = ScanLightingController()
    private static var previewTask: Task<Void, Never>?

    /// Plays a smooth 2.4s live visual preview of NEELx's Studio Light rim (and optional Chromatic Prism) from Settings.
    static func previewStudioLight() {
        previewTask?.cancel()
        previewController.hide()
        previewController.begin(forEnrollment: false, allowWhenUnlocked: true)
        previewTask = Task { @MainActor in
            previewController.applyBoost(level: 0.72)
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled else { return }
            if NEELxSettings.shared.chromaticFlashEnabled {
                previewController.flashChallenge(tint: .cyan)
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                previewController.flashChallenge(tint: .magenta)
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                previewController.clearFlashChallenge()
            } else {
                try? await Task.sleep(for: .milliseconds(700))
            }
            guard !Task.isCancelled else { return }
            previewController.hide()
        }
    }

    /// Active brightness animation task — cancelled cleanly whenever a new target arrives.
    private var brightnessAnimTask: Task<Void, Never>?
    /// Delayed orderOut task when fading out gracefully — cancelled if a new scan starts mid-fade.
    private var fadeOutTask: Task<Void, Never>?

    private let darkTriggerLuminance: Double = 0.26
    private let targetLuminance: Double = 0.33
    private let adjustCooldown: TimeInterval = 0.24

    func begin(forEnrollment: Bool = false, allowWhenUnlocked: Bool = false) {
        fadeOutTask?.cancel()
        fadeOutTask = nil
        brightnessAnimTask?.cancel()
        brightnessAnimTask = nil

        self.isActive = true
        self.forEnrollment = forEnrollment
        self.allowWhenUnlocked = allowWhenUnlocked
        self.currentBoostLevel = 0
        self.lastAdjustmentAt = 0
        if let lightView {
            lightView.challengeColor = nil
            lightView.intensity = 0
            lightView.needsDisplay = true
        }
        panel?.alphaValue = 0
    }

    /// Closed-loop per-frame controller: evaluates live frame/face brightness AND backlit
    /// silhouette contrast (bright window behind a darkened face), then smoothly breathes up
    /// hardware backlight + Studio Light rim halo until the face is clearly illuminated.
    func consider(_ image: CGImage, faceVisible: Bool = false, faceBox: CGRect? = nil) {
        guard isActive else { return }
        guard UserDefaults.standard.object(forKey: "NEELxSecurity.scanLightEnabled") as? Bool ?? true else {
            return
        }
        if !forEnrollment && !allowWhenUnlocked {
            guard LockMonitor.isScreenActuallyLocked() else { return }
        }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAdjustmentAt >= adjustCooldown else { return }

        let frameLum = Self.meanLuminance(image, normalizedRect: nil)
        let centerRect = CGRect(x: 0.30, y: 0.25, width: 0.40, height: 0.50)
        let effectiveLum: Double
        let isBacklitSilhouette: Bool

        if let faceBox, faceVisible {
            let faceLum = Self.meanLuminance(image, normalizedRect: faceBox)
            isBacklitSilhouette = faceLum < 0.24 && (frameLum - faceLum) >= 0.12
            // When backlit, prioritize the face's own darkness rather than letting the sunlit window hide it
            effectiveLum = isBacklitSilhouette ? faceLum : (0.75 * faceLum + 0.25 * frameLum)
        } else {
            let centerLum = Self.meanLuminance(image, normalizedRect: centerRect)
            isBacklitSilhouette = centerLum < 0.26 && (frameLum - centerLum) >= 0.12
            effectiveLum = min(centerLum, frameLum)
        }

        // Naturally well-lit non-backlit room -> stay completely invisible
        if currentBoostLevel == 0 && !isBacklitSilhouette && effectiveLum >= darkTriggerLuminance && (faceVisible || frameLum >= targetLuminance) {
            return
        }

        // Face is clearly illuminated -> hold comfortably steady without further changes
        if faceVisible && !isBacklitSilhouette && effectiveLum >= targetLuminance {
            return
        }

        // Smooth single-target boost calculation (avoids jittery stair-stepping!)
        let desiredLevel: Double
        if currentBoostLevel == 0 {
            if effectiveLum < 0.12 {
                desiredLevel = 0.78
            } else if effectiveLum < 0.20 {
                desiredLevel = 0.52
            } else {
                desiredLevel = 0.34
            }
        } else {
            let deficit = max(targetLuminance - effectiveLum, 0.04)
            let step = min(max(deficit * 0.75, 0.12), 0.22)
            desiredLevel = min(currentBoostLevel + step, 0.95)
        }

        let nextLevel = min(max(desiredLevel, currentBoostLevel), 0.95)
        guard nextLevel > currentBoostLevel + 0.03 else { return }

        lastAdjustmentAt = now
        currentBoostLevel = nextLevel
        applyBoost(level: nextLevel)
    }

    private func applyBoost(level: Double) {
        // 1. Capture original hardware brightness once, then smoothly ease backlight over 260ms
        if savedBrightness == nil, let current = DisplayBrightnessBridge.getMainBrightness() {
            savedBrightness = current
            currentHardwareBrightness = current
        }
        if let base = savedBrightness {
            let targetBrightness = max(base, min(0.92, base + Float(level) * (0.92 - base)))
            animateHardwareBrightness(to: targetBrightness, duration: 0.26)
        }

        // 2. Smoothly fade in the feathered TrueTone ambient halo (zero sharp edges)
        ensureOverlayVisible()
        guard let panel, let lightView else { return }
        lightView.intensity = CGFloat(level)
        lightView.forEnrollment = forEnrollment
        lightView.needsDisplay = true

        let targetAlpha: CGFloat = forEnrollment
            ? min(0.68, 0.28 + CGFloat(level) * 0.40)
            : min(0.86, 0.35 + CGFloat(level) * 0.51)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = targetAlpha
        }
    }

    private func ensureOverlayVisible() {
        guard panel == nil, let screen = NotchGeometry.preferredScreen() ?? NSScreen.main else { return }
        let window = NotchWindow(contentRect: screen.frame)
        let view = ScanLightHaloView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.forEnrollment = forEnrollment
        window.contentView = view
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        if forEnrollment {
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        }
        panel = window
        lightView = view
        window.orderFrontRegardless()
        if !forEnrollment, let skyLight = NotchSkyLight.shared {
            skyLight.delegate(window)
            delegated = true
        }
    }

    /// Gently pulses a feathered randomized chromatic edge tint for anti-video-replay verification.
    func flashChallenge(tint: ChromaticFlashTint) {
        if savedBrightness == nil, let current = DisplayBrightnessBridge.getMainBrightness() {
            savedBrightness = current
            currentHardwareBrightness = current
        }
        if let base = savedBrightness {
            animateHardwareBrightness(to: max(base, 0.90), duration: 0.06)
        }
        ensureOverlayVisible()
        guard let panel, let lightView else { return }
        lightView.challengeColor = tint.nsColor
        lightView.needsDisplay = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.045
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0.92
        }
        panel.displayIfNeeded()
    }

    /// Immediately clears the chromatic tint back to the ambient halo (or off) so subsequent frames never inherit stale tint.
    func clearFlashChallenge() {
        guard let panel, let lightView else { return }
        lightView.challengeColor = nil
        lightView.needsDisplay = true
        if currentBoostLevel == 0 {
            panel.alphaValue = 0
        }
        panel.displayIfNeeded()
    }

    /// Gracefully dissolves the halo and smoothly eases hardware backlight back to your exact original level.
    func hide() {
        isActive = false
        currentBoostLevel = 0

        if let original = savedBrightness {
            let restoreTarget = original
            savedBrightness = nil
            animateHardwareBrightness(to: restoreTarget, duration: 0.36)
        }

        guard let closingPanel = panel else { return }
        let wasDelegated = delegated
        panel = nil
        lightView = nil
        delegated = false

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            closingPanel.animator().alphaValue = 0
        }

        fadeOutTask?.cancel()
        fadeOutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 340_000_000)
            if wasDelegated { NotchSkyLight.shared?.undelegate(closingPanel) }
            closingPanel.orderOut(nil)
        }
    }

    /// Smooth 60fps cubic-eased hardware display backlight ramp (eliminates jarring step-jumps).
    private func animateHardwareBrightness(to target: Float, duration: TimeInterval) {
        brightnessAnimTask?.cancel()
        let start = currentHardwareBrightness ?? DisplayBrightnessBridge.getMainBrightness() ?? target
        guard abs(target - start) > 0.005 else {
            DisplayBrightnessBridge.setMainBrightness(target)
            currentHardwareBrightness = target
            return
        }

        let steps = max(Int(duration * 60.0), 6)
        let stepNs = UInt64((duration / Double(steps)) * 1_000_000_000)
        brightnessAnimTask = Task { @MainActor [weak self] in
            for i in 1...steps {
                guard !Task.isCancelled else { return }
                let t = Float(i) / Float(steps)
                // Smooth easeInOutCubic curve
                let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                let value = start + (target - start) * eased
                DisplayBrightnessBridge.setMainBrightness(value)
                self?.currentHardwareBrightness = value
                try? await Task.sleep(nanoseconds: stepNs)
            }
        }
    }

    /// Computes perceptual luminance (0...1) over the whole image or a Vision normalized sub-rect (bottom-left origin).
    nonisolated static func meanLuminance(_ image: CGImage, normalizedRect: CGRect? = nil) -> Double {
        let side = 32
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let sourceImage: CGImage
        if let rect = normalizedRect {
            let iw = Double(image.width)
            let ih = Double(image.height)
            let cropRect = CGRect(
                x: max(0, Double(rect.minX) * iw),
                y: max(0, (1.0 - Double(rect.maxY)) * ih),
                width: max(4, Double(rect.width) * iw),
                height: max(4, Double(rect.height) * ih)
            ).intersection(CGRect(x: 0, y: 0, width: iw, height: ih))
            sourceImage = image.cropping(to: cropRect) ?? image
        } else {
            sourceImage = image
        }

        let success = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard success else { return 1 }

        var total = 0.0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            total += 0.2126 * Double(bytes[index]) + 0.7152 * Double(bytes[index + 1]) + 0.0722 * Double(bytes[index + 2])
        }
        return total / Double(side * side) / 255.0
    }
}

/// Safe dynamic loader for Apple's DisplayServices built-in backlight API.
private enum DisplayBrightnessBridge {
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    }()

    private static let getFn: GetBrightnessFn? = {
        guard let handle, let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetBrightnessFn.self)
    }()

    private static let setFn: SetBrightnessFn? = {
        guard let handle, let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetBrightnessFn.self)
    }()

    static func getMainBrightness() -> Float? {
        guard let getFn else { return nil }
        var value: Float = -1
        let rc = getFn(CGMainDisplayID(), &value)
        guard rc == 0, value >= 0, value <= 1 else { return nil }
        return value
    }

    static func setMainBrightness(_ brightness: Float) {
        guard let setFn else { return }
        let clamped = min(max(brightness, 0.05), 1.0)
        _ = setFn(CGMainDisplayID(), clamped)
    }
}

/// Luxury Apple Studio Light perimeter softbox & Siri-grade spectral chromatic rim:
/// draws a silky feathered rounded-display border light (crystal-clear screen center, luminous
/// multi-layered edge bloom + delicate hairline specular lip) with zero boxy edges or harsh neon slabs.
@MainActor
private final class ScanLightHaloView: NSView {
    var intensity: CGFloat = 0.4
    var forEnrollment: Bool = false
    var challengeColor: NSColor? = nil

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let isChallenge = challengeColor != nil

        // Warm 3800K champagne-ivory Studio Light for dark/backlit rooms;
        // refined pastel-blended spectral rim for Chromatic Flash.
        let primaryColor: NSColor
        let secondaryColor: NSColor
        if let challengeColor {
            // Higher spectral purity during the brief ~120ms pulse so cyan/magenta cleanly
            // registers on skin before Apple's ISP Auto-White-Balance compensates.
            primaryColor = challengeColor.blended(withFraction: 0.12, of: .white) ?? challengeColor
            secondaryColor = challengeColor.blended(withFraction: 0.28, of: .white) ?? challengeColor
        } else {
            primaryColor = NSColor(calibratedRed: 1.0, green: 0.968, blue: 0.915, alpha: 1.0)
            secondaryColor = NSColor(calibratedRed: 1.0, green: 0.985, blue: 0.955, alpha: 1.0)
        }

        // 1. Soft atmospheric radial falloff (keeps Studio Light center crystal clear;
        //    gives the brief Chromatic Flash enough uniform spectral fill to register reliably)
        let c0: CGFloat = isChallenge ? 0.22 : (forEnrollment ? 0.0 : intensity * 0.03)
        let c1: CGFloat = isChallenge ? 0.36 : (forEnrollment ? intensity * 0.06 : intensity * 0.12)
        let c2: CGFloat = isChallenge ? 0.62 : (forEnrollment ? intensity * 0.28 : intensity * 0.44)
        let c3: CGFloat = isChallenge ? 0.90 : min(0.86, 0.34 + intensity * 0.48)

        let colors = [
            primaryColor.withAlphaComponent(c0).cgColor,
            primaryColor.withAlphaComponent(c1).cgColor,
            primaryColor.withAlphaComponent(c2).cgColor,
            primaryColor.withAlphaComponent(c3).cgColor,
        ] as CFArray

        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors,
            locations: [0.0, 0.48, 0.80, 1.0]
        ) {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let outerRadius = hypot(bounds.width * 0.5, bounds.height * 0.5)
            let innerRadius = min(bounds.width, bounds.height) * 0.28

            ctx.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: innerRadius,
                endCenter: center,
                endRadius: outerRadius,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // 2. Sculpted rounded-display Studio Light softbox rim (concentrates clean illumination around the bezel)
        let cornerRadius: CGFloat = 24
        let rimLayers: [(inset: CGFloat, width: CGFloat, alpha: CGFloat)] = isChallenge
            ? [(6, 18, 0.42), (16, 36, 0.24), (32, 68, 0.12)]
            : [(6, 16, min(0.55, 0.20 + intensity * 0.35)),
               (18, 38, min(0.32, 0.10 + intensity * 0.22)),
               (38, 76, min(0.16, 0.05 + intensity * 0.11))]

        for layer in rimLayers {
            let rect = bounds.insetBy(dx: layer.inset, dy: layer.inset)
            guard rect.width > 40, rect.height > 40 else { continue }
            let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setStrokeColor(secondaryColor.withAlphaComponent(layer.alpha).cgColor)
            ctx.setLineWidth(layer.width)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
}
