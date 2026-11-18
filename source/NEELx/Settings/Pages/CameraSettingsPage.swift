//
//  CameraSettingsPage.swift
//  NEELx
//

import SwiftUI

struct CameraSettingsPage: View {
    @Bindable var pocController: POCController
    @State private var devices: [CameraDevice] = CameraDeviceCatalog.availableDevices()
    @Bindable private var settings = NEELxSettings.shared
    @State private var verifier = ContinuityDeviceVerifier.shared
    @State private var proximityGuard = DeviceProximityGuard.shared
    @State private var passkeyCompanion = PasskeyCompanionManager.shared
    @State private var isPairingSheetPresented = false
    @State private var previewCamera = CameraManager()
    @State private var isPreviewShown = false

    @State private var isUnlocking = false
    @State private var sessionError: String?

    private var isSessionUnlocked: Bool { pocController.isSessionUnlocked }

    var body: some View {
        ZStack(alignment: .top) {
            lockedState
                .opacity(isSessionUnlocked ? 0 : 1)
                .allowsHitTesting(!isSessionUnlocked)
                .accessibilityHidden(isSessionUnlocked)

            unlockedState
                .opacity(isSessionUnlocked ? 1 : 0)
                .allowsHitTesting(isSessionUnlocked)
                .accessibilityHidden(!isSessionUnlocked)
        }
        .animation(SettingsMetrics.stateTransitionAnimation, value: isSessionUnlocked)
        // Gated on isSessionUnlocked so the header's refresh icon doesn't
        // show while this page is displaying the locked prompt.
        .preference(
            key: HeaderTrailingActionKey.self,
            value: isSessionUnlocked ? HeaderAction(perform: refreshDevices) : nil
        )
        .onAppear { pocController.refreshCredentialStatus() }
        .onChange(of: isSessionUnlocked) { _, unlocked in
            guard !unlocked else { return }
            hidePreview()
        }
        .onDisappear { hidePreview() }
        // Password/name/enrollment flows run in the notch, outside this
        // window, so nothing else prompts a re-check once one closes.
        .onChange(of: NotchOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            pocController.refreshCredentialStatus()
        }
    }

    // MARK: - Locked

    private var lockedState: some View {
        SettingsEmptyStateView(
            icon: "lock.fill",
            message: "Session locked",
            buttonTitle: isUnlocking ? "Authenticating…" : "Unlock session",
            isButtonEnabled: !isUnlocking,
            caption: sessionError,
            action: unlock
        )
    }

    // MARK: - Unlocked

    private var unlockedState: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsGroup {
                cameraPicker(title: "Default", selection: $settings.defaultCameraID)
                SettingsGroupDivider()
                cameraPicker(title: "Built-in display", selection: $settings.builtInDisplayCameraID)
                SettingsGroupDivider()
                cameraPicker(title: "External display", selection: $settings.externalDisplayCameraID)
            }

            // SECTION 2: iPhone & iPad Pro Continuity Camera (Option 3 - Desk Stand / Studio Optics)
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "iPhone & iPad Pro Camera (Continuity Studio)")
                SettingsGroup {
                    SettingsRowContent(
                        title: "Use iPhone / iPad Pro Camera",
                        subtitle: "Wirelessly connects your iPhone (iOS 16+) or iPad Pro camera for studio optics and 4K clarity. Works on any desk stand, wireless charger, kickstand case, or monitor mount — no special clip required! Automatically falls back to built-in webcam when disconnected.",
                        subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                    ) {
                        NEELxToggle(isOn: $settings.allowContinuityCamera)
                    }

                    if settings.allowContinuityCamera {
                        SettingsGroupDivider()

                        SettingsRowContent(
                            title: "Dual-Path Concurrent Unlock",
                            subtitle: "Polls both your Mac's built-in webcam and your phone/tablet camera simultaneously — unlocks from whichever sees your face first.",
                            subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                        ) {
                            NEELxToggle(isOn: $settings.dualCameraConcurrentUnlock)
                        }

                        SettingsGroupDivider()

                        SettingsRowContent(
                            title: "Device Proximity Guard (Bluetooth LE)",
                            subtitle: "Requires your paired phone/tablet to be within arm's reach (< 1.5m) to arm biometric unlock, preventing unauthorized wake-ups.",
                            subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                        ) {
                            NEELxToggle(isOn: $settings.deviceProximityGuardEnabled)
                        }
                    }
                }

                // Continuity hardware requirements & cross-check card
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: verifier.isRequirementsMet ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(verifier.isRequirementsMet ? Color.green : Color.yellow)
                            .font(.system(size: 14))

                        Text(verifier.isRequirementsMet ? "Camera Hardware Verified" : "Camera Requirements Cross-Check")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(verifier.isRequirementsMet ? Color.green : Color.yellow)

                        Spacer()

                        Button(action: {
                            verifier.refresh()
                            refreshDevices()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Check")
                            }
                            .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    Text(verifier.diagnosticMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius).fill(SettingsMetrics.rowColor))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius)
                        .strokeBorder(verifier.isRequirementsMet ? Color.green.opacity(0.3) : Color.yellow.opacity(0.3), lineWidth: 1)
                )
            }

            // SECTION 3: Native Mobile Biometric Companion (Option 2 - Zero App Required)
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Mobile Biometric Companion (Native Passkey)")
                SettingsGroup {
                    SettingsRowContent(
                        title: "Use Phone Face ID / Fingerprint",
                        subtitle: "Unlock your Mac using your phone's native hardware biometrics (iPhone TrueDepth or Android BiometricPrompt) via standard FIDO2 Passkeys. Zero mobile app installation required.",
                        subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                    ) {
                        NEELxToggle(isOn: $settings.passkeyCompanionEnabled)
                    }

                    if settings.passkeyCompanionEnabled {
                        SettingsGroupDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Paired Biometric Device")
                                    .font(.subheadline.weight(.medium))
                                Text(passkeyCompanion.isPaired ? passkeyCompanion.pairedDeviceName : "No phone paired yet")
                                    .font(.caption)
                                    .foregroundStyle(passkeyCompanion.isPaired ? Color.green : Color.secondary)
                            }
                            Spacer()
                            if passkeyCompanion.isPaired {
                                Button("Unpair") {
                                    passkeyCompanion.unpairDevice()
                                }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                            } else {
                                Button(action: {
                                    if isPairingSheetPresented {
                                        passkeyCompanion.stopPairingSession()
                                        isPairingSheetPresented = false
                                    } else {
                                        passkeyCompanion.startPairingSession()
                                        isPairingSheetPresented = true
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "qrcode")
                                        Text(isPairingSheetPresented ? "Hide QR" : "Pair via QR Code")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.blue.opacity(0.2)))
                                    .overlay(Capsule().strokeBorder(Color.blue.opacity(0.5), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                }

                // QR Code Pairing Drawer
                if isPairingSheetPresented && !passkeyCompanion.isPaired {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Scan with Phone Camera to Pair")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Close") {
                                passkeyCompanion.stopPairingSession()
                                isPairingSheetPresented = false
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        if let qr = passkeyCompanion.pairingQRImage {
                            Image(nsImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 170, height: 170)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.3)))
                        }

                        VStack(spacing: 4) {
                            Text("1. Open Camera on iPhone (iOS 16+) or Android (9+)")
                                .font(.caption.weight(.medium))
                            Text("2. Tap the link to open Mobile Safari or Chrome")
                                .font(.caption.weight(.medium))
                            Text("3. Confirm with Face ID or Fingerprint — done in 5 seconds!")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.green)
                        }
                        .foregroundStyle(.secondary)

                        if let url = passkeyCompanion.pairingURL {
                            Text(url)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius).fill(SettingsMetrics.rowColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius)
                            .strokeBorder(Color.blue.opacity(0.4), lineWidth: 1)
                    )
                }

                // Companion hardware requirements & cross-check card
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: passkeyCompanion.isRequirementsMet ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(passkeyCompanion.isRequirementsMet ? Color.green : Color.yellow)
                            .font(.system(size: 14))

                        Text(passkeyCompanion.isRequirementsMet ? "Companion Requirements Verified" : "Companion Requirements Cross-Check")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(passkeyCompanion.isRequirementsMet ? Color.green : Color.yellow)

                        Spacer()

                        Button(action: {
                            passkeyCompanion.evaluateRequirements()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Check")
                            }
                            .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    Text(passkeyCompanion.diagnosticMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius).fill(SettingsMetrics.rowColor))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius)
                        .strokeBorder(passkeyCompanion.isRequirementsMet ? Color.green.opacity(0.3) : Color.yellow.opacity(0.3), lineWidth: 1)
                )
            }

            SettingsSectionTitle(text: "Preview")
            .padding(.bottom, -4)
            previewArea
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius)
                        .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
                )

            if isPreviewShown, let error = previewCamera.errorMessage {
                SettingsCaption(text: error)
            }
        }
        .onChange(of: settings.defaultCameraID) { restartPreview() }
        .onChange(of: settings.builtInDisplayCameraID) { restartPreview() }
        .onChange(of: settings.externalDisplayCameraID) { restartPreview() }
        .onChange(of: settings.allowContinuityCamera) {
            refreshDevices()
            verifier.refresh()
            restartPreview()
        }
    }

    /// Live feed, or a placeholder until "Show preview" is tapped — opening
    /// this page alone should never request camera access.
    @ViewBuilder
    private var previewArea: some View {
        if isPreviewShown {
            CameraPreviewView(session: previewCamera.session, faces: [])
        } else {
            ZStack {
                SettingsMetrics.rowColor
                SettingsPrimaryButton(title: "Show preview", action: showPreview)
            }
        }
    }

    private func showPreview() {
        isPreviewShown = true
        Task { await previewCamera.start() }
    }

    private func hidePreview() {
        guard isPreviewShown else { return }
        previewCamera.stop()
        isPreviewShown = false
    }

    /// `CameraManager` only re-resolves its device on `start()`, so restart
    /// it to reflect a new pick. No-op while hidden — picking a camera must
    /// not be what quietly turns it on.
    private func restartPreview() {
        guard isPreviewShown else { return }
        previewCamera.stop()
        Task { await previewCamera.start() }
    }

    private func cameraPicker(title: String, selection: Binding<String?>) -> some View {
        SettingsRowContent(title: title) {
            SettingsMenuPickerPill(label: cameraLabel(for: selection.wrappedValue)) {
                Button("System default") { selection.wrappedValue = nil }
                ForEach(devices) { device in
                    Button(device.name) { selection.wrappedValue = device.id }
                }
            }
        }
    }

    /// Fired by the header's refresh icon (see `HeaderTrailingActionKey`).
    private func refreshDevices() {
        devices = CameraDeviceCatalog.availableDevices()
    }

    private func cameraLabel(for id: String?) -> String {
        guard let id, let device = devices.first(where: { $0.id == id }) else {
            return "System default"
        }
        return device.name
    }

    // MARK: - Actions

    private func unlock() {
        isUnlocking = true
        sessionError = nil
        Task {
            await pocController.unlockSession()
            sessionError = pocController.sessionError
            isUnlocking = false
        }
    }
}
