//
//  GeneralSettingsPage.swift
//  NEELx
//

import OSLog
import SwiftUI

struct GeneralSettingsPage: View {
    @Bindable var coordinator: FaceUnlockCoordinator
    @Bindable private var settings = NEELxSettings.shared

    @AppStorage("NEELx.triggerModifier") private var triggerModifier = "shift"
    @AppStorage("NEELxSecurity.scanLightEnabled") private var scanLightEnabled = true

    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    /// Refreshed on `didChangeScreenParametersNotification` so the picker
    /// reflects displays connecting/disconnecting while Settings is open.
    @State private var screens: [NSScreen] = NSScreen.screens
    /// Refreshed when the app regains focus, so granting the permission in
    /// System Settings clears the prompt below without a relaunch.
    @State private var inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess

    private var needsInputMonitoring: Bool {
        settings.unlockTriggers.contains(.onSpace) && inputMonitoring != .granted
    }

    /// Dev-only: under Xcode the reading above is Xcode's permission, not
    ///  NEELx's, so it's meaningless. See `SpaceKeyMonitor.isLaunchedByXcode`.
    private var hasInheritedXcodePermission: Bool {
        settings.unlockTriggers.contains(.onSpace) && SpaceKeyMonitor.isLaunchedByXcode
    }

    var body: some View {
        SettingsGroup {
            SettingsRowContent(title: "Launch at login") {
                NEELxToggle(isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        launchAtLoginEnabled = newValue
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginEnabled = !newValue
                            launchAtLoginError = error.localizedDescription
                        }
                    }
                ))
            }
            SettingsGroupDivider()
            SettingsRowContent(title: "Enable Face Unlock") {
                NEELxToggle(isOn: $coordinator.isEnabled)
            }
            SettingsGroupDivider()
            SettingsRowContent(
                title: "Face ID for System Touch ID & Password Prompts",
                subtitle: "Automatically approves macOS Touch ID & password popups everywhere (System Settings, installs, Saved Passwords, Finder, Keychain) — excludes Apple Pay & payments."
            ) {
                NEELxToggle(isOn: $settings.systemAuthPromptsEnabled)
            }
            SettingsGroupDivider()
            UnlockTriggerPicker(selection: $settings.unlockTriggers, isEnabled: coordinator.isEnabled)
            SettingsGroupDivider()
            displayPicker()
            SettingsGroupDivider()
            SettingsRowContent(title: "Scan key", subtitle: "Enable On key above. Press and release; either side works.") {
                Picker("Scan key", selection: $triggerModifier) {
                    Text("Shift").tag("shift")
                    Text("Control").tag("control")
                    Text("Option").tag("option")
                }.labelsHidden().frame(width: 120)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess
        }
        .onChange(of: settings.unlockTriggers) { oldValue, newValue in
            // Only prompt on the transition into selecting "On space".
            SpaceKeyMonitor.log.info("unlockTriggers changed: old=\(String(describing: oldValue), privacy: .public) new=\(String(describing: newValue), privacy: .public) state=\(String(describing: inputMonitoring), privacy: .public)")
            if newValue.contains(.onSpace), !oldValue.contains(.onSpace), inputMonitoring != .granted {
                SpaceKeyMonitor.requestInputMonitoringAccess()
                // tccd flips notDetermined -> denied just after the call
                // returns, so re-read on the next beat rather than inline.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess
                }
            }
        }
        if let launchAtLoginError {
            SettingsCaption(text: launchAtLoginError)
        }
        if hasInheritedXcodePermission {
            SettingsCaption(text: "Running from Xcode — permission checks resolve against Xcode’s grants, not NEELx’s, so this reading is meaningless. Launch NEELx.app on its own to see the real state.")
        } else if needsInputMonitoring {
            inputMonitoringNotice()
        }

        SettingsCaption(text: "On wake scans after opening the lid or waking the display. Use the selected modifier or a trackpad action to avoid typing a character. macOS controls which inputs wake sleeping hardware. On key also starts a scan when the lock screen is already visible. Letters, Space and Return are not offered because they can alter or submit the password field.")
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Behaviour")
            SettingsGroup {
                SettingsRowContent(title: "Retry on notch hover") {
                    NEELxToggle(isOn: $settings.retryOnHover)
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "Auto retry once after failure") {
                    NEELxToggle(isOn: $settings.autoRetryOnce)
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Adaptive Studio Light illumination",
                    subtitle: "Smoothly raises screen brightness and a warm perimeter Studio Light rim in dark or backlit rooms, then restores your original brightness."
                ) {
                    HStack(spacing: 10) {
                        Button("Preview") {
                            ScanLightingController.previewStudioLight()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        NEELxToggle(isOn: $scanLightEnabled)
                    }
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Subtle unlock chime",
                    subtitle: "Plays a soft muted glass cue timed with the Face ID checkmark and Trackpad haptic."
                ) {
                    NEELxToggle(isOn: $settings.unlockSoundEnabled)
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Walk-away auto-lock (Presence Lock)",
                    subtitle: "Checks the camera briefly after keyboard/mouse idle and locks your Mac if you've stepped away."
                ) {
                    NEELxToggle(isOn: $settings.presenceAutoLockEnabled)
                }
                if settings.presenceAutoLockEnabled {
                    SettingsGroupDivider()
                    SettingsRowContent(title: "Lock after idle") {
                        Picker("Lock after idle", selection: $settings.presenceAutoLockSeconds) {
                            Text("30 sec").tag(30)
                            Text("1 min").tag(60)
                            Text("2 min").tag(120)
                            Text("5 min").tag(300)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "Haptic feedback") {
                    NEELxToggle(isOn: $settings.hapticFeedbackEnabled)
                }
                SettingsGroupDivider()
                SettingsSteppedSliderRowContent(
                    title: "Face detection duration",
                    valueLabel: "\(settings.faceDetectionSeconds)s",
                    index: Binding(
                        get: { Double(settings.faceDetectionSeconds - NEELxSettings.faceDetectionRange.lowerBound) },
                        set: { settings.faceDetectionSeconds = NEELxSettings.faceDetectionRange.lowerBound + Int($0.rounded()) }
                    ),
                    stopCount: NEELxSettings.faceDetectionRange.count
                )
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Animation")
            SettingsGroup {
                SettingsRowContent(title: "Show animation") {
                    NEELxToggle(isOn: $settings.showUnlockAnimation)
                }
                SettingsGroupDivider()
                UnlockAnimationPicker(
                    selection: $settings.unlockAnimationStyle,
                    isEnabled: settings.showUnlockAnimation
                )
            }
        }
    }

    /// Shown while "On space" is selected but Input Monitoring isn't granted.
    private func inputMonitoringNotice() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsCaption(text: "“On key” needs keyboard-observation access. Enable NEELx in Accessibility, and Input Monitoring if macOS requests it. Quit and reopen NEELx after changing permission.")
            Button("Open Accessibility settings") {
                // Covers the rare install with no Accessibility grant at all.
                SpaceKeyMonitor.requestInputMonitoringAccess()
                openSystemSettings(pane: "Privacy_Accessibility")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(NEELxTheme.accent)
        }
    }

    private func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func displayPicker() -> some View {
        SettingsRowContent(title: "Display on") {
            SettingsMenuPickerPill(label: displayLabel) {
                Button("Main display") {
                    settings.preferredDisplayID = nil
                    settings.preferredDisplayName = nil
                }
                ForEach(screens.compactMap(NamedScreen.init), id: \.id) { screen in
                    Button(screen.name) {
                        settings.preferredDisplayID = screen.id
                        settings.preferredDisplayName = screen.name
                    }
                }
            }
        }
    }

    /// A connected screen with its stable ID already unwrapped, so the
    /// picker's `ForEach` doesn't need to filter/force-unwrap inline.
    private struct NamedScreen {
        let id: String
        let name: String

        init?(_ screen: NSScreen) {
            guard let id = screen.stableDisplayID else { return nil }
            self.id = id
            self.name = screen.localizedName
        }
    }

    private var displayLabel: String {
        guard let targetID = settings.preferredDisplayID else { return "Main display" }
        if let connected = screens.first(where: { $0.stableDisplayID == targetID }) {
            return connected.localizedName
        }
        // Picked, but not currently connected — say so rather than showing
        // a bare ID or falling back to another display's name.
        guard let name = settings.preferredDisplayName else { return "Selected display (disconnected)" }
        return "\(name) (disconnected)"
    }
}
