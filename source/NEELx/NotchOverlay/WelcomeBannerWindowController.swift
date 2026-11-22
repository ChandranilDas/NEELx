//
//  WelcomeBannerWindowController.swift
//  NEELx
//
//  Floating popup message displayed at the top of the screen right after successful
//  face authorization and unlock: "Welcome Back (Name)!", appearing from above and
//  gracefully disappearing back to above.
//

import AppKit
import SwiftUI

@MainActor
final class WelcomeBannerWindowController {
    static let shared = WelcomeBannerWindowController()

    private var window: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var host: Host?

    @Observable
    final class Host {
        var name: String
        var isVisible = false

        init(name: String) {
            self.name = name
        }
    }

    private init() {}

    func show(name: String) {
        guard NEELxSettings.shared.welcomeBannerEnabled else { return }
        // Item #44: In Discreet Lock-Screen Privacy Mode, suppress floating name banners in public
        guard !NEELxSettings.shared.discreetUnlockMode else { return }

        dismissTask?.cancel()
        dismissTask = nil
        dismissImmediately()

        guard let screen = NotchGeometry.preferredScreen() ?? NSScreen.main else { return }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanName.isEmpty ? (NSFullUserName().isEmpty ? "User" : NSFullUserName()) : cleanName

        let host = Host(name: displayName)
        self.host = host

        let hostingView = NSHostingView(rootView: WelcomeBannerView(host: host))
        hostingView.sizingOptions = []

        // Sized dynamically with minimal footprint
        let charCount = CGFloat(displayName.count)
        let bannerWidth: CGFloat = max(210, min(380, charCount * 8.5 + 160))
        let bannerHeight: CGFloat = 46

        // Position at top center, right below notch or top bezel
        let topY = screen.frame.maxY - bannerHeight - (screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top + 8 : 12)
        let originX = screen.frame.minX + (screen.frame.width - bannerWidth) / 2
        let frame = NSRect(x: originX, y: topY, width: bannerWidth, height: bannerHeight)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hostingView
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        self.window = panel

        // 1. Smooth entrance from above
        withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) {
            host.isVisible = true
        }

        // 2. Minimal duration (~1.8s) then smooth retract back to above
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1800))
            guard let self, !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.28)) {
                self.host?.isVisible = false
            }

            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.dismissImmediately()
        }
    }

    func dismissImmediately() {
        dismissTask?.cancel()
        dismissTask = nil
        window?.orderOut(nil)
        window = nil
        host = nil
    }
}

struct WelcomeBannerView: View {
    let host: WelcomeBannerWindowController.Host

    var body: some View {
        HStack(spacing: 8) {
            // Emerald checkmark badge
            ZStack {
                Circle()
                    .fill(Color(red: 0.19, green: 0.82, blue: 0.35).opacity(0.22))
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color(red: 0.19, green: 0.82, blue: 0.35))
            }

            Text("Welcome Back, \(host.name)!")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.92))
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.24),
                                    Color(red: 0.19, green: 0.82, blue: 0.35).opacity(0.45),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: Color.black.opacity(0.50), radius: 14, y: 6)
        }
        // Floating translation: appears from above (offset y = -36) and retracts back above
        .offset(y: host.isVisible ? 0 : -36)
        .scaleEffect(host.isVisible ? 1.0 : 0.88)
        .opacity(host.isVisible ? 1.0 : 0.0)
    }
}
