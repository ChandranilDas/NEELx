//
//  CameraActivityMonitor.swift
//  NEELx
//
//  Item #40: Menu Bar Camera Activity Reason Indicator — Explains transparently
//  to the user why NEELx is accessing the camera or confirms when it is in complete standby.
//

import Foundation
import Observation

enum CameraActivityState: Equatable {
    case standby
    case presenceCheck
    case scanningToUnlock
    case enrollingFace
    case testingInFaceLab

    var title: String {
        switch self {
        case .standby:
            return "Standby (Idle)"
        case .presenceCheck:
            return "Checking Presence"
        case .scanningToUnlock:
            return "Scanning to Unlock"
        case .enrollingFace:
            return "Enrolling Face Profile"
        case .testingInFaceLab:
            return "Testing in Face Lab"
        }
    }

    var isActive: Bool {
        self != .standby
    }
}

@Observable
@MainActor
final class CameraActivityMonitor {
    static let shared = CameraActivityMonitor()

    private(set) var state: CameraActivityState = .standby

    private init() {}

    func update(to newState: CameraActivityState) {
        self.state = newState
    }
}
