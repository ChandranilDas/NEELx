//
//  NotchPanelStyle.swift
//  NEELx
//
//  Which silhouette the overlay panel wears on a given screen — passed down
//  through the environment so onboarding's step views can adapt without a parameter.
//

import SwiftUI

nonisolated enum NotchPanelStyle: Sendable {
    /// Inverted top corners, flush with the screen's top edge.
    case notch
    /// Fully-rounded pill / floating rounded rectangle, detached from the edge.
    case pill
}

private struct NotchPanelStyleKey: EnvironmentKey {
    nonisolated static let defaultValue: NotchPanelStyle = .notch
}
extension EnvironmentValues {
    var notchPanelStyle: NotchPanelStyle {
        get { self[NotchPanelStyleKey.self] }
        set { self[NotchPanelStyleKey.self] = newValue }
    }
}
