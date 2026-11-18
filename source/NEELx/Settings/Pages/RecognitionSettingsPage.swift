//
//  RecognitionSettingsPage.swift
//  NEELx
//

import SwiftUI

struct RecognitionSettingsPage: View {
    @Bindable var coordinator: FaceUnlockCoordinator
    @Bindable var pocController: POCController
    @Bindable private var settings = NEELxSettings.shared
    private let depthDownloader = DepthModelDownloader.shared

    @State private var isUnlocking = false
    @State private var sessionError: String?

    /// Read from `POCController`, not a local copy — same reasoning as
    /// `PasswordSettingsPage`.
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
        .onAppear { pocController.refreshCredentialStatus() }
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
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup {
                SettingsOptionSliderRowContent(
                    title: "Match confidence",
                    stepLabels: MatchConfidenceLevel.allCases.map(\.title),
                    index: matchConfidenceIndex,
                    stopCount: MatchConfidenceLevel.allCases.count
                )

                SettingsGroupDivider()

                SettingsOptionSliderRowContent(
                    title: "Detection distance",
                    stepLabels: DetectionDistanceLevel.allCases.map(\.title),
                    index: detectionDistanceIndex,
                    stopCount: DetectionDistanceLevel.allCases.count
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Liveness & 3D Depth")
                SettingsGroup {
                    SettingsRowContent(
                        title: "3D Neural Depth (ANE)",
                        subtitle: depthSubtitle,
                        subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                    ) {
                        if NeuralDepthAnalyzer.shared.isModelAvailable || depthDownloader.state == .installed {
                            NEELxToggle(isOn: $settings.neuralDepthEnabled)
                        } else {
                            switch depthDownloader.state {
                            case .downloading(let progress, _):
                                HStack(spacing: 8) {
                                    ProgressView(value: progress)
                                        .frame(width: 72)
                                    Button("Cancel") { depthDownloader.cancel() }
                                        .buttonStyle(.plain)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            case .compiling:
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Optimizing…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            case .idle, .failed:
                                SettingsPrimaryButton(title: "Download (47 MB)") {
                                    depthDownloader.startDownload()
                                }
                            case .installed:
                                NEELxToggle(isOn: $settings.neuralDepthEnabled)
                            }
                        }
                    }

                    SettingsGroupDivider()

                    SettingsRowContent(
                        title: "Active Chromatic Flash",
                        subtitle: "Flashes a brief randomized color pulse (~110ms) to verify live skin reflection and defeat 4K video replay attacks.",
                        subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                    ) {
                        NEELxToggle(isOn: $settings.chromaticFlashEnabled)
                    }

                    SettingsGroupDivider()

                    SettingsRowContent(
                        title: "Face ID for Installs & Saved Passwords",
                        subtitle: "Automatically approves macOS Touch ID & password prompts (app installs, System Settings, Saved Passwords) with Face ID when you look at your Mac.",
                        subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                    ) {
                        NEELxToggle(isOn: $settings.systemAuthPromptsEnabled)
                    }

                    SettingsGroupDivider()

                    SettingsRowContent(
                        title: "Silent Adaptive Learning",
                        subtitle: "Automatically adapts to gradual changes (glasses, beard, lighting) from high-confidence 3D-verified unlocks.",
                        subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                    ) {
                        NEELxToggle(isOn: $settings.adaptiveLearningEnabled)
                    }

                    SettingsGroupDivider()

                    SettingsRowContent(
                        title: "Require Attention & Eye Gaze",
                        subtitle: "Verifies your eyes are open and facing the screen, alongside glare and device-bezel spoof detection.",
                        subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                    ) {
                        Text("Always on")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SettingsSectionTitle(text: "Encrypted Security Audit Log")
                    Spacer()
                    if !SecurityAuditLog.shared.entries.isEmpty {
                        Button("Clear") {
                            SecurityAuditLog.shared.clear()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                SettingsGroup {
                    SettingsRowContent(
                        title: "Record unlock & spoof attempts",
                        subtitle: "Logs unlock events and encrypted snapshots of blocked intruders/spoofs strictly offline under your Touch ID key.",
                        subtitleMaxWidth: SettingsMetrics.rowSubtitleMaxWidth
                    ) {
                        NEELxToggle(isOn: $settings.intruderLogEnabled)
                    }

                    if !SecurityAuditLog.shared.entries.isEmpty {
                        SettingsGroupDivider()
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(SecurityAuditLog.shared.entries.prefix(6)) { entry in
                                HStack(alignment: .center, spacing: 10) {
                                    if let jpeg = entry.snapshotJPEG, let img = NSImage(data: jpeg) {
                                        Image(nsImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 34, height: 34)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Image(systemName: entry.kind.systemImage)
                                            .foregroundStyle(entry.kind == .unlocked ? .green : .orange)
                                            .frame(width: 24)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(entry.kind.title)
                                                .font(.caption.weight(.semibold))
                                            Spacer()
                                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(entry.detail)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
    }

    // MARK: - 3D Depth subtitle

    private var depthSubtitle: String {
        if NeuralDepthAnalyzer.shared.isModelAvailable || depthDownloader.state == .installed {
            return "Depth Anything V2 analyzes 3D nose protrusion, facial curvature, and head-to-background depth cliff on Apple Neural Engine."
        }
        switch depthDownloader.state {
        case .downloading(_, let status): return status
        case .compiling: return "Compiling Core ML model for your Mac's Neural Engine…"
        case .failed(let msg): return "Download failed: \(msg)"
        case .idle, .installed: return "Download Apple's Depth Anything V2 Core ML engine (47 MB) for 3D anti-spoofing."
        }
    }

    // MARK: - Match confidence

    /// Nearest of the three snap points to whatever's stored, in case the
    /// value doesn't land exactly on one of the stops.
    private var matchConfidenceLevel: MatchConfidenceLevel {
        .nearest(to: coordinator.matchThreshold)
    }

    private var matchConfidenceIndex: Binding<Double> {
        Binding(
            get: { matchConfidenceLevel.sliderIndex },
            set: { coordinator.matchThreshold = MatchConfidenceLevel.from(sliderIndex: $0).threshold }
        )
    }

    // MARK: - Detection distance

    private var detectionDistanceLevel: DetectionDistanceLevel {
        .nearest(to: settings.minimumFaceWidth)
    }

    private var detectionDistanceIndex: Binding<Double> {
        Binding(
            get: { detectionDistanceLevel.sliderIndex },
            set: { settings.minimumFaceWidth = DetectionDistanceLevel.from(sliderIndex: $0).minimumFaceWidth }
        )
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

/// The three selectable points on the "Match confidence" slider — named
/// rather than exposing the raw cosine-similarity threshold directly.
private enum MatchConfidenceLevel: Int, CaseIterable {
    case lessStrict, standard, moreStrict

    var title: String {
        switch self {
        case .lessStrict: return "Less strict"
        case .standard: return "Default"
        case .moreStrict: return "More strict"
        }
    }

    var threshold: Float {
        switch self {
        case .lessStrict: return 0.58
        case .standard: return 0.63
        case .moreStrict: return 0.68
        }
    }

    /// Position in `allCases` — same role as `AutoLockInterval.sliderIndex`.
    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> Self {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .standard
    }

    static func nearest(to threshold: Float) -> Self {
        allCases.min { abs($0.threshold - threshold) < abs($1.threshold - threshold) } ?? .standard
    }
}

/// The three selectable points on the "Detection distance" slider.
private enum DetectionDistanceLevel: Int, CaseIterable {
    case close, standard, far

    var title: String {
        switch self {
        case .close: return "Close"
        case .standard: return "Default"
        case .far: return "Far"
        }
    }

    var minimumFaceWidth: Float {
        switch self {
        case .close: return 0.23
        case .standard: return 0.19
        case .far: return 0.15
        }
    }

    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> Self {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .standard
    }

    static func nearest(to width: Float) -> Self {
        allCases.min { abs($0.minimumFaceWidth - width) < abs($1.minimumFaceWidth - width) } ?? .standard
    }
}
