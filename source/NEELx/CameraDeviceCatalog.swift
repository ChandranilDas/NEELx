//
//  CameraDeviceCatalog.swift
//  NEELx
//
//  Resolves the app's camera preference (flat default, or split by built-in vs. external display) into the device to open.
//

import AVFoundation
import AppKit

struct CameraDevice: Identifiable, Hashable {
    let id: String // AVCaptureDevice.uniqueID
    let name: String
}

enum CameraDeviceCatalog {
    static func availableDevices() -> [CameraDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external]
        if NEELxSettings.shared.allowContinuityCamera {
            types.append(.continuityCamera)
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// True if the currently-active screen is the Mac's built-in display
    /// (vs. an external monitor) — used to pick between the built-in/
    /// external camera overrides.
    static func isUsingBuiltInDisplay() -> Bool {
        guard let screen = NSScreen.main,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return true }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    /// True when the MacBook lid is closed and only external displays are active (clamshell mode).
    static func isClamshellMode() -> Bool {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return false }
        let hasActiveBuiltIn = screens.contains { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            return CGDisplayIsBuiltin(id) != 0
        }
        return !hasActiveBuiltIn
    }

    /// Display-specific override, then smart clamshell external/Continuity camera fallback, then flat default, then system default.
    static func resolvedDevice() -> AVCaptureDevice? {
        let settings = NEELxSettings.shared
        let clamshell = isClamshellMode()
        let onBuiltIn = !clamshell && isUsingBuiltInDisplay()

        let preferredID = onBuiltIn
            ? (settings.builtInDisplayCameraID ?? settings.defaultCameraID)
            : (settings.externalDisplayCameraID ?? settings.defaultCameraID)

        if let preferredID, let device = AVCaptureDevice(uniqueID: preferredID) {
            // In clamshell mode, avoid opening the closed-lid built-in camera if an external/Continuity camera exists
            if !(clamshell && device.deviceType == .builtInWideAngleCamera) {
                return device
            }
        }

        if clamshell || settings.allowContinuityCamera {
            let types: [AVCaptureDevice.DeviceType] = settings.allowContinuityCamera
                ? [.continuityCamera, .external]
                : [.external]
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: types,
                mediaType: .video,
                position: .unspecified
            )
            if settings.allowContinuityCamera, let continuity = discovery.devices.first(where: { $0.deviceType == .continuityCamera && $0.isConnected && !$0.isSuspended }) {
                return continuity
            } else if clamshell, let external = discovery.devices.first {
                return external
            }
        }

        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }
}
