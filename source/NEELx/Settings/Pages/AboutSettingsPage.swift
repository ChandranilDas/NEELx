//
//  AboutSettingsPage.swift
//  NEELx
//

import SwiftUI
import AppKit

struct AboutSettingsPage: View {
    @Bindable var updater: UpdaterController
    let environment: AppEnvironment

    /// Secret-tap state for revealing the Debug/Face Lab sidebar section —
    /// see `AppEnvironment.isDebugSectionRevealed`. A pause over a second
    /// resets the count, so this requires 5 *consecutive* taps.
    @State private var iconTapCount = 0
    @State private var lastTapDate: Date?
    @State private var didCopyDiagnostics = false
    @State private var showFeedbackSheet = false
    @State private var showCheckMySetupSheet = false
    @State private var showResetConfirmation = false
    private let requiredTapCount = 5
    private let tapResetInterval: TimeInterval = 1.0

    private var versionString: String {
        NEELxConfig.versionString
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .onTapGesture(perform: handleIconTap)

            Text("NEELx")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SettingsMetrics.textPrimary)

            Text(versionString)
                .font(.system(size: 12))
                .foregroundStyle(SettingsMetrics.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)

        SettingsGroup {
            SettingsActionRowContent(
                title: "Check My Setup",
                subtitle: "Inspect camera, permissions, neural models, login item, and system readiness.",
                buttonTitle: "Check…"
            ) {
                showCheckMySetupSheet = true
            }

            SettingsGroupDivider()

            SettingsActionRowContent(
                title: "Official NEELx Website",
                buttonTitle: "Visit"
            ) {
                if let url = NEELxConfig.officialWebsiteURL {
                    NSWorkspace.shared.open(url)
                }
            }

            SettingsGroupDivider()

            SettingsActionRowContent(
                title: "Send Feedback or Report Bug",
                buttonTitle: "Send Feedback"
            ) {
                showFeedbackSheet = true
            }

            SettingsGroupDivider()

            SettingsActionRowContent(
                title: "Copy Diagnostics for GitHub Issue",
                buttonTitle: didCopyDiagnostics ? "Copied!" : "Copy"
            ) {
                copyDiagnosticsToClipboard()
            }

            SettingsGroupDivider()

            SettingsActionRowContent(
                title: "Check for Updates",
                subtitle: updater.statusText,
                buttonTitle: updater.canCheckForUpdates ? "Check" : "Checking…",
                isEnabled: updater.canCheckForUpdates
            ) {
                updater.checkForUpdates()
            }

            SettingsGroupDivider()

            SettingsRowContent(
                title: "Automatic update checks",
                subtitle: "Checks GitHub Releases daily and lets you install new NEELx versions in one click."
            ) {
                NEELxToggle(isOn: $updater.automaticallyChecksForUpdates)
            }

            SettingsGroupDivider()

            SettingsActionRowContent(
                title: "Based on Glance · MIT license",
                buttonTitle: "Source"
            ) {
                if let url = URL(string: "https://github.com/jonnyoo/glance") {
                    NSWorkspace.shared.open(url)
                }
            }

            SettingsGroupDivider()

            SettingsActionRowContent(
                title: "Reset to Factory Defaults",
                subtitle: "Wipes all enrolled faces, clears passwords, and restores clean defaults.",
                buttonTitle: "Reset…"
            ) {
                showResetConfirmation = true
            }

            SettingsGroupDivider()

            SettingsActionRowContent(
                title: "Quit NEELx",
                subtitle: "Completely quits all background biometric processes so you can move or delete the app.",
                buttonTitle: "Quit"
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .sheet(isPresented: $showFeedbackSheet) {
            FeedbackSheetView {
                showFeedbackSheet = false
            }
        }
        .sheet(isPresented: $showCheckMySetupSheet) {
            CheckMySetupSheetView(environment: environment)
        }
        .alert("Reset NEELx to Factory Defaults?", isPresented: $showResetConfirmation) {
            Button("Reset and Start Setup", role: .destructive) {
                NEELxSettings.shared.resetToFactoryDefaults()
                for window in NSApp.windows where window.canBecomeMain {
                    window.close()
                }
                OnboardingController.startFlow(resumingAt: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All enrolled face templates and preferences will be permanently wiped. Setup will restart fresh.")
        }
    }

    /// Copies a strictly privacy-scrubbed Markdown environment summary (zero names, passwords, or biometric data)
    /// so open-source testers can paste actionable device info into GitHub Issues in one click.
    private func copyDiagnosticsToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(NEELxConfig.diagnosticsMarkdown(), forType: .string)
        didCopyDiagnostics = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            didCopyDiagnostics = false
        }
    }

    private func handleIconTap() {
        let now = Date()
        if let lastTapDate, now.timeIntervalSince(lastTapDate) > tapResetInterval {
            iconTapCount = 0
        }
        lastTapDate = now
        iconTapCount += 1
        guard iconTapCount >= requiredTapCount else { return }
        iconTapCount = 0
        environment.isDebugSectionRevealed = true
    }
}
