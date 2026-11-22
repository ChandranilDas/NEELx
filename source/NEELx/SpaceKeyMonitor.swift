//
//  SpaceKeyMonitor.swift
//  NEELx
// Non-consuming keyboard observation, active only while locked and opted in.
// Only modifier releases can trigger a scan; printable keys are never offered.

import Foundation
import IOKit.hid
import OSLog

@MainActor
final class SpaceKeyMonitor {
    /// Traces the Input Monitoring handshake, otherwise invisible since TCC decisions happen out of process.
    static let log = Logger(subsystem: "local.neelx", category: "inputmonitoring")

    /// Fires on key-down only, not release or auto-repeat.
    var onSpaceKeyDown: (() -> Void)?

    /// Item #45: Fires when the user presses any standard alphanumeric or typing key while locked,
    /// signalling manual password entry or Touch ID interaction to safely cancel in-flight face scans.
    var onAnyKeyPressedWhileScanning: (() -> Void)?

    private var manager: IOHIDManager?
    private var pressedUsages = Set<UInt32>()
    static var selectedKey: String {
        UserDefaults.standard.string(forKey: "NEELx.triggerModifier") ?? "shift"
    }
    private func accept(usage: UInt32, isDown: Bool) {
        let supported: Set<UInt32>
        switch Self.selectedKey {
        case "control": supported = [224, 228]
        case "option": supported = [226, 230]
        default: supported = [225, 229]
        }
        guard supported.contains(usage) else { return }
        if isDown { pressedUsages.insert(usage) }
        else if pressedUsages.remove(usage) != nil { onSpaceKeyDown?() }
    }

    // MARK: - Input Monitoring permission (static — callable without an instance)

    /// `denied` matters on its own: once set, no API can re-prompt — only System Settings can undo it.
    enum InputMonitoringAccess {
        case granted
        case denied
        case notDetermined
    }

    static var inputMonitoringAccess: InputMonitoringAccess {
        let raw = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let state: InputMonitoringAccess
        switch raw {
        case kIOHIDAccessTypeGranted: state = .granted
        case kIOHIDAccessTypeDenied: state = .denied
        default: state = .notDetermined
        }
        log.info("checkAccess -> \(String(describing: state), privacy: .public) (raw \(raw.rawValue)), xcodeLaunched=\(isLaunchedByXcode, privacy: .public)")
        return state
    }

    /// Never prompts. True whenever Accessibility is granted (see file header), so it tracks `KeystrokeInjector.isAccessibilityTrusted()`.
    static func hasInputMonitoringAccess() -> Bool {
        inputMonitoringAccess == .granted
    }

    /// True when launched by Xcode's Run button, which makes TCC decisions attribute to Xcode, not NEELx — test permission
    /// behavior from an independently launched copy instead (`open /Applications/NEELx.app`, or a build in /Applications).
    static var isLaunchedByXcode: Bool {
        ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil
    }

    /// Near-always a no-op: already satisfied through Accessibility. Skipped under Xcode, where it would attribute to Xcode instead.
    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        guard !isLaunchedByXcode else {
            log.error("requestAccess SKIPPED — launched by Xcode, request would be attributed to Xcode")
            return hasInputMonitoringAccess()
        }
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        log.info("requestAccess -> \(granted, privacy: .public)")
        return granted
    }

    // MARK: - Lifecycle

    /// Idempotent; fails closed if access was revoked between the caller's check and here.
    func start() {
        guard manager == nil else { return }

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Match physical keyboards only, not every HID device.
        let match: [String: Int] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)

        // Capture-less C callback; `self` threaded through the context pointer. `passUnretained` is safe since this object
        // always `stop()`s (unregistering) before deallocation.
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(mgr, { context, _, _, value in
            guard let context else { return }
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad) else { return }
            let usage = IOHIDElementGetUsage(element)
            let isDown = IOHIDValueGetIntegerValue(value) != 0
            let monitor = Unmanaged<SpaceKeyMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                if [UInt32(224), 225, 226, 228, 229, 230].contains(usage) {
                    monitor.accept(usage: usage, isDown: isDown)
                } else if isDown {
                    // Item #45: Standard keypress (e.g. typing password) cancels in-flight scan
                    monitor.onAnyKeyPressedWhileScanning?()
                }
            }
        }, context)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        // Ground truth about HID access (unlike IOHIDCheckAccess); logged since a failure here is a silent no-op on the lock screen.
        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            Self.log.error("IOHIDManagerOpen FAILED (0x\(String(result, radix: 16), privacy: .public)) — trigger key will not be seen")
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return
        }
        Self.log.info("listening for the selected modifier on the lock screen")
        manager = mgr
    }

    /// Stops listening. Idempotent.
    func stop() {
        guard let mgr = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        pressedUsages.removeAll()
    }

    deinit {
        // Always stopped before teardown (on unlock/disable), so nothing to unwind here.
    }
}
