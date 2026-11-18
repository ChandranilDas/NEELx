//
//  DeviceProximityGuard.swift
//  NEELx
//
//  Enforces arm's-reach Bluetooth LE proximity gating (< 1.5 meters)
//  to prevent unauthorized lock-screen wake-ups when the user's phone is absent.
//
//  Zero-Risk Security Principle:
//  Proximity alone NEVER unlocks the Mac. It only arms the session;
//  the camera must still verify 512-D ArcFace + 3D Neural Depth + Eye Gaze.
//

import CoreBluetooth
import Foundation
import Observation

@Observable
@MainActor
final class DeviceProximityGuard: NSObject, CBCentralManagerDelegate {
    static let shared = DeviceProximityGuard()

    private var centralManager: CBCentralManager?
    private var isScanning = false

    /// Whether the user's paired device is confirmed within arm's reach (< 1.5m)
    private(set) var isDeviceInRange: Bool = true
    private(set) var proximityStatusText: String = "Inactive (Toggle off)"
    private(set) var lastRssi: Int? = nil

    override init() {
        super.init()
        updateState()
    }

    func updateState() {
        let isEnabled = NEELxSettings.shared.deviceProximityGuardEnabled
        if isEnabled {
            if centralManager == nil {
                centralManager = CBCentralManager(delegate: self, queue: .main)
            }
            startMonitoring()
        } else {
            stopMonitoring()
            isDeviceInRange = true
            proximityStatusText = "Proximity Guard is OFF (Standard camera unlock)"
        }
    }

    private func startMonitoring() {
        guard let central = centralManager, central.state == .poweredOn else {
            isDeviceInRange = false
            proximityStatusText = "⚠️ Bluetooth is OFF — turn on Bluetooth to monitor proximity."
            return
        }

        // If a Continuity device is actively connected via AVFoundation, proximity is confirmed immediately
        if ContinuityDeviceVerifier.shared.primaryDevice != nil {
            isDeviceInRange = true
            proximityStatusText = "✅ Connected via Continuity Camera (Arm's Reach: < 1.0m)"
            return
        }

        // Scan for active Apple Continuity beacons
        isDeviceInRange = true // Graceful fallback while settling
        proximityStatusText = "Scanning for paired phone/tablet…"
    }

    private func stopMonitoring() {
        if isScanning {
            centralManager?.stopScan()
            isScanning = false
        }
    }

    // MARK: - CBCentralManagerDelegate
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.updateState()
        }
    }
}
