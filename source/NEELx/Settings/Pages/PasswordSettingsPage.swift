//
//  PasswordSettingsPage.swift
//  NEELx
//

import SwiftUI

struct PasswordSettingsPage: View {
    @Bindable var pocController: POCController
    @Bindable private var settings = NEELxSettings.shared

    @State private var isUnlocking = false
    @State private var sessionError: String?
    @State private var statusMessage: String?

    /// Read from `POCController`, not a local copy — `SessionAutoLocker` can
    /// lock the session from outside this view.
    private var isSessionUnlocked: Bool { pocController.isSessionUnlocked }

    /// "No password stored" takes priority over lock state entirely, so
    /// removal doesn't fall back to an "unlock session" prompt for a
    /// session that no longer protects anything.
    private enum PageState: Equatable {
        case noPassword
        case locked
        case unlocked
    }

    private var pageState: PageState {
        guard pocController.hasStoredPassword else { return .noPassword }
        return isSessionUnlocked ? .unlocked : .locked
    }

    var body: some View {
        ZStack(alignment: .top) {
            noPasswordState
                .opacity(pageState == .noPassword ? 1 : 0)
                // Hidden from hit-testing and accessibility while faded out.
                .allowsHitTesting(pageState == .noPassword)
                .accessibilityHidden(pageState != .noPassword)

            lockedState
                .opacity(pageState == .locked ? 1 : 0)
                .allowsHitTesting(pageState == .locked)
                .accessibilityHidden(pageState != .locked)

            unlockedState
                .opacity(pageState == .unlocked ? 1 : 0)
                .allowsHitTesting(pageState == .unlocked)
                .accessibilityHidden(pageState != .unlocked)
        }
        .animation(SettingsMetrics.stateTransitionAnimation, value: pageState)
        .onAppear { pocController.refreshCredentialStatus() }
        // The onboarding password step runs in the notch, outside this
        // view's hierarchy, so nothing else prompts a re-check once it closes.
        .onChange(of: NotchOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            pocController.refreshCredentialStatus()
            FaceEnrollmentStore.shared.reloadIfUnlocked()
        }
    }

    // MARK: - No password stored

    private var noPasswordState: some View {
        SettingsEmptyStateView(
            icon: "lock.fill",
            message: "Set up a password",
            buttonTitle: "Set password",
            caption: statusMessage,
            action: { OnboardingController.startPasswordOnly() }
        )
    }

    // MARK: - Locked

    private var lockedState: some View {
        VStack(spacing: SettingsMetrics.emptyStateSpacing) {
            SettingsEmptyStateView(
                icon: "lock.fill",
                message: "Session locked",
                buttonTitle: isUnlocking ? "Authenticating…" : "Unlock session",
                isButtonEnabled: !isUnlocking,
                caption: sessionError,
                action: unlock
            )
            if sessionError != nil {
                Button("Reset Credentials & Start Fresh") {
                    resetCredentialsAndStartFresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Unlocked

    private var unlockedState: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsGroup {
                SettingsRowContent(title: "Password encrypted") {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsMetrics.textSecondary)
                }

                SettingsGroupDivider()

                SettingsRowContent(title: "Authorization limit", subtitle: "8 hours maximum; 5 failed scans require Touch ID or your Mac password again.") {
                    Text("Hardened")
                }

                SettingsGroupDivider()

                SettingsRowContent(title: "Change password") {
                    SettingsPrimaryButton(title: "Change", compact: true) {
                        OnboardingController.startPasswordOnly()
                    }
                }

                SettingsGroupDivider()

                SettingsRowContent(
                    title: "Forget saved password",
                    subtitle: "Removes your stored password while keeping your enrolled face profile and settings intact. You can continue using Visual Verification mode."
                ) {
                    HoldToConfirmButton(title: "Forget", action: forgetPasswordOnly)
                }

                SettingsGroupDivider()

                SettingsRowContent(title: "Remove password & face profile") {
                    HoldToConfirmButton(title: "Remove All", action: removePassword)
                }
            }

            if let statusMessage {
                SettingsCaption(text: statusMessage)
            }
        }
    }

    // MARK: - Actions

    private func unlock() {
        isUnlocking = true
        sessionError = nil
        Task {
            await pocController.unlockSession()
            sessionError = pocController.sessionError
            // Face store is encrypted under the same session key, so reload
            // it now rather than leaving Your Face stuck showing "locked".
            FaceEnrollmentStore.shared.reloadIfUnlocked()
            isUnlocking = false
        }
    }

    /// Item #42: Deletes ONLY the stored password payload, leaving enrolled face templates intact.
    private func forgetPasswordOnly() {
        do {
            try pocController.forgetPasswordOnly()
            statusMessage = "Password forgotten. Your enrolled face profile is preserved."
        } catch {
            statusMessage = "Couldn't remove password: \(error.localizedDescription)"
        }
    }

    /// Face samples must be deleted before the password/session key —
    /// `deletePassword()` clears the cached session key, and deleting the
    /// face store requires an unlocked session.
    private func removePassword() {
        do {
            FaceEnrollmentStore.shared.deleteAll()
            try SecureCredentialManager.deletePassword()
            pocController.refreshCredentialStatus()
            statusMessage = "Password and face enrollment removed."
        } catch {
            statusMessage = "Couldn't remove: \(error.localizedDescription)"
        }
    }

    private func resetCredentialsAndStartFresh() {
        SecureCredentialManager.resetAllState()
        pocController.refreshCredentialStatus()
        NEELxSettings.shared.hasCompletedOnboarding = false
        NEELxSettings.shared.onboardingResumeStep = nil
        sessionError = nil
        FaceEnrollmentStore.shared.reloadIfUnlocked()
        OnboardingController.startFlow()
    }
}
