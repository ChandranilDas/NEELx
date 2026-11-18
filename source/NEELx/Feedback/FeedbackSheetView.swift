//
//  FeedbackSheetView.swift
//  NEELx
//
//  Native SwiftUI feedback & bug-reporting sheet for open-source / beta testers.
//  Supports 1-click direct Cloudflare/Brevo submission with screenshot attachments,
//  installed desktop + webmail app chooser (preventing blank browser tabs),
//  pre-filled GitHub Issues, and clipboard export — with privacy-scrubbed Mac diagnostics.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug = "Bug Report"
    case suggestion = "Feature Idea"
    case experience = "Unlock Experience"

    var id: String { rawValue }

    var githubLabel: String {
        switch self {
        case .bug:        return "bug"
        case .suggestion: return "enhancement"
        case .experience: return "feedback"
        }
    }

    var systemImage: String {
        switch self {
        case .bug:        return "ant.fill"
        case .suggestion: return "lightbulb.fill"
        case .experience: return "sparkles"
        }
    }
}

struct FeedbackScreenshot: Identifiable {
    let id = UUID()
    let name: String
    let preview: NSImage
    let jpegData: Data
}

struct InstalledEmailApp: Identifiable, Hashable {
    let id: String
    let name: String
    let appURL: URL
    let bundleID: String
}

enum EmailAppCatalog {
    /// Web browsers sometimes register for `mailto:` on macOS without a configured webmail handler,
    /// which causes clicking a mailto link to open a blank browser tab. Filter them out of native mail apps.
    private static let excludedBrowserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "app.zen-browser.zen",
    ]

    static func installedDesktopApps() -> [InstalledEmailApp] {
        guard let probe = URL(string: "mailto:support@example.com") else { return [] }
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: probe)
        var seen = Set<String>()
        var apps: [InstalledEmailApp] = []

        for url in urls {
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier ?? url.path
            if excludedBrowserBundleIDs.contains(bundleID) || seen.contains(bundleID) {
                continue
            }
            seen.insert(bundleID)
            let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            apps.append(InstalledEmailApp(id: bundleID, name: displayName, appURL: url, bundleID: bundleID))
        }

        // Always put Apple Mail first if installed, then alphabetical
        return apps.sorted { a, b in
            if a.bundleID == "com.apple.mail" { return true }
            if b.bundleID == "com.apple.mail" { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

struct FeedbackSheetView: View {
    var onDismiss: () -> Void

    @State private var category: FeedbackCategory = .experience
    @State private var rating: Int = 5
    @State private var titleText: String = ""
    @State private var messageText: String = ""
    @State private var includeDiagnostics: Bool = true
    @State private var screenshots: [FeedbackScreenshot] = []
    @State private var installedMailApps: [InstalledEmailApp] = EmailAppCatalog.installedDesktopApps()
    @State private var isSubmitting: Bool = false
    @State private var submitResult: String?
    @State private var submitFailed: Bool = false
    @State private var didCopy: Bool = false

    private let maxScreenshots = 3

    private var hasWebhook: Bool {
        !NEELxConfig.feedbackWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasEmail: Bool {
        !NEELxConfig.feedbackEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSubmit: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send NEELx Feedback")
                        .font(.title3.weight(.semibold))
                    Text("Help shape NEELx — bug reports, screenshots, and feature ideas go straight to the developer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Category picker
            Picker("Category", selection: $category) {
                ForEach(FeedbackCategory.allCases) { item in
                    Label(item.rawValue, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Optional 1-5 star experience rating
            HStack(spacing: 8) {
                Text("Unlock smoothness:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .foregroundStyle(star <= rating ? .yellow : .secondary.opacity(0.5))
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            TextField("Short summary (optional)", text: $titleText)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Details")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $messageText)
                    .font(.body)
                    .frame(height: 105)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }

            // Screenshot attachments (up to 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Screenshots (\(screenshots.count)/\(maxScreenshots))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        pasteScreenshotFromClipboard()
                    } label: {
                        Label("Paste Image", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .controlSize(.small)
                    .disabled(screenshots.count >= maxScreenshots)

                    Button {
                        pickScreenshotsFromDisk()
                    } label: {
                        Label("Add Screenshot…", systemImage: "photo.badge.plus")
                            .font(.caption)
                    }
                    .controlSize(.small)
                    .disabled(screenshots.count >= maxScreenshots)
                }

                if !screenshots.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(screenshots) { shot in
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: shot.preview)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 78, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 7))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7)
                                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                        )
                                    Button {
                                        screenshots.removeAll { $0.id == shot.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white, .black.opacity(0.75))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 4, y: -4)
                                }
                                .padding(.top, 4)
                                .padding(.trailing, 4)
                            }
                        }
                    }
                }
            }

            Toggle(isOn: $includeDiagnostics) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include privacy-scrubbed Mac diagnostics")
                        .font(.caption.weight(.medium))
                    Text("Mac model, macOS version, camera name, ANE 3D Depth status & settings. Zero passwords or face data.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            if let submitResult {
                Text(submitResult)
                    .font(.caption)
                    .foregroundStyle(submitFailed ? .red : .green)
            }

            Divider()

            HStack(spacing: 10) {
                Button(didCopy ? "Copied!" : "Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(composedMarkdownBody(), forType: .string)
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { didCopy = false }
                }

                if hasEmail {
                    Menu("Email") {
                        if !installedMailApps.isEmpty {
                            Section("Email Apps on This Mac") {
                                ForEach(installedMailApps) { app in
                                    Button(app.name) {
                                        openInDesktopMailApp(app)
                                    }
                                }
                            }
                        }
                        Section("Webmail (Opens Pre-filled Draft)") {
                            Button("Gmail (Web)") { openWebmail(.gmail) }
                            Button("Outlook (Web)") { openWebmail(.outlook) }
                            Button("Yahoo Mail (Web)") { openWebmail(.yahoo) }
                        }
                    }
                    .disabled(!canSubmit)
                    .onAppear {
                        installedMailApps = EmailAppCatalog.installedDesktopApps()
                    }
                }

                Spacer()

                if hasWebhook {
                    Button("GitHub Issue") { openPreFilledGitHubIssue() }
                        .disabled(!canSubmit)

                    Button(isSubmitting ? "Sending…" : "Send Directly") {
                        Task { await submitToWebhook() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                } else {
                    Button("GitHub Issue") { openPreFilledGitHubIssue() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSubmit)
                }
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    // MARK: - Screenshot Helpers

    private func pickScreenshotsFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Select Screenshots"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        let remaining = maxScreenshots - screenshots.count
        for url in panel.urls.prefix(remaining) {
            if let image = NSImage(contentsOf: url),
               let compressed = encodeScreenshot(image, suggestedName: url.deletingPathExtension().lastPathComponent) {
                screenshots.append(compressed)
            }
        }
    }

    private func pasteScreenshotFromClipboard() {
        guard screenshots.count < maxScreenshots else { return }
        if let image = NSImage(pasteboard: .general),
           let compressed = encodeScreenshot(image, suggestedName: "pasted-screenshot-\(screenshots.count + 1)") {
            screenshots.append(compressed)
            submitFailed = false
            submitResult = "Attached screenshot from clipboard."
        } else {
            submitFailed = true
            submitResult = "No image found on clipboard — take a screenshot (Cmd+Ctrl+Shift+4) or click Add Screenshot."
        }
    }

    /// Resizes an image to max 1440px longest side and JPEG-encodes at 0.82 quality for fast, crisp email attachments.
    private func encodeScreenshot(_ image: NSImage, suggestedName: String) -> FeedbackScreenshot? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let srcW = cgImage.width
        let srcH = cgImage.height
        guard srcW > 0, srcH > 0 else { return nil }

        let maxDim: CGFloat = 1440
        let scale = min(1.0, maxDim / CGFloat(max(srcW, srcH)))
        let dstW = max(1, Int(CGFloat(srcW) * scale))
        let dstH = max(1, Int(CGFloat(srcH) * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        guard let scaledCG = ctx.makeImage() else { return nil }

        let rep = NSBitmapImageRep(cgImage: scaledCG)
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            return nil
        }

        let safeBase = suggestedName
            .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
            .prefix(50)
        let name = "\(safeBase.isEmpty ? "screenshot" : String(safeBase)).jpg"
        let preview = NSImage(cgImage: scaledCG, size: NSSize(width: dstW, height: dstH))
        return FeedbackScreenshot(name: name, preview: preview, jpegData: jpegData)
    }

    // MARK: - Composition

    private func composedTitle() -> String {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return "[\(category.rawValue)] \(trimmed)" }
        return "[\(category.rawValue)] NEELx Beta Feedback (\(rating)/5 ★)"
    }

    private func composedMarkdownBody() -> String {
        let stars = String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
        var body = """
        **Category:** \(category.rawValue)
        **Rating:** \(stars) (\(rating)/5)

        \(messageText.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        if includeDiagnostics {
            body += "\n\n" + NEELxConfig.diagnosticsMarkdown()
        }
        return body
    }

    private func composedPlainEmailBody() -> String {
        let stars = String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
        var body = """
        Category: \(category.rawValue)
        Rating: \(stars) (\(rating)/5)

        \(messageText.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        if includeDiagnostics {
            body += "\n\n" + NEELxConfig.diagnosticsMarkdown()
        }
        return body
    }

    // MARK: - Delivery Actions

    private func openPreFilledGitHubIssue() {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(NEELxConfig.githubRepository)/issues/new"
        components.queryItems = [
            URLQueryItem(name: "title", value: composedTitle()),
            URLQueryItem(name: "labels", value: category.githubLabel),
            URLQueryItem(name: "body", value: composedMarkdownBody()),
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
            submitFailed = false
            submitResult = "Opened pre-filled GitHub Issue in your browser — thank you!"
        }
    }

    private func openInDesktopMailApp(_ app: InstalledEmailApp) {
        // Apple Mail supports native NSSharingService with real image attachments + pre-filled To/Subject/Body
        if app.bundleID == "com.apple.mail", let service = NSSharingService(named: .composeEmail) {
            service.recipients = [NEELxConfig.feedbackEmail]
            service.subject = composedTitle()
            var items: [Any] = [composedPlainEmailBody()]
            for shot in screenshots {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(shot.name)
                if (try? shot.jpegData.write(to: tempURL, options: .atomic)) != nil {
                    items.append(tempURL)
                }
            }
            service.perform(withItems: items)
            submitFailed = false
            submitResult = screenshots.isEmpty
                ? "Opened draft in Apple Mail — review and press Send!"
                : "Opened draft in Apple Mail with \(screenshots.count) screenshot(s) attached!"
            return
        }

        // Launch the exact desktop email client chosen by the user (never a blank browser tab)
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = NEELxConfig.feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: composedTitle()),
            URLQueryItem(name: "body", value: composedPlainEmailBody()),
        ]
        guard let mailtoURL = components.url else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([mailtoURL], withApplicationAt: app.appURL, configuration: config) { _, error in
            Task { @MainActor in
                if let error {
                    submitFailed = true
                    submitResult = "Couldn't open \(app.name): \(error.localizedDescription)"
                } else {
                    submitFailed = false
                    submitResult = screenshots.isEmpty
                        ? "Opened draft in \(app.name) — review and press Send!"
                        : "Opened draft in \(app.name) (tip: use 'Send Directly' or Apple Mail to auto-attach screenshots)."
                }
            }
        }
    }

    private enum WebmailProvider {
        case gmail, outlook, yahoo
    }

    private func openWebmail(_ provider: WebmailProvider) {
        let to = NEELxConfig.feedbackEmail
        let subject = composedTitle()
        let body = composedPlainEmailBody()

        var components: URLComponents
        let label: String
        switch provider {
        case .gmail:
            components = URLComponents(string: "https://mail.google.com/mail/")!
            components.queryItems = [
                URLQueryItem(name: "view", value: "cm"),
                URLQueryItem(name: "fs", value: "1"),
                URLQueryItem(name: "to", value: to),
                URLQueryItem(name: "su", value: subject),
                URLQueryItem(name: "body", value: body),
            ]
            label = "Gmail"
        case .outlook:
            components = URLComponents(string: "https://outlook.live.com/mail/0/deeplink/compose")!
            components.queryItems = [
                URLQueryItem(name: "to", value: to),
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: body),
            ]
            label = "Outlook Web"
        case .yahoo:
            components = URLComponents(string: "https://compose.mail.yahoo.com/")!
            components.queryItems = [
                URLQueryItem(name: "to", value: to),
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: body),
            ]
            label = "Yahoo Mail"
        }

        if let url = components.url {
            NSWorkspace.shared.open(url)
            submitFailed = false
            submitResult = screenshots.isEmpty
                ? "Opened pre-filled draft in \(label) — press Send!"
                : "Opened pre-filled draft in \(label) (tip: click 'Send Directly' to auto-attach your \(screenshots.count) screenshot(s))."
        }
    }

    private func submitToWebhook() async {
        guard let url = URL(string: NEELxConfig.feedbackWebhookURL) else { return }
        isSubmitting = true
        submitResult = nil
        submitFailed = false
        defer { isSubmitting = false }

        let encodedAttachments: [[String: String]] = screenshots.map { shot in
            [
                "name": shot.name,
                "content": shot.jpegData.base64EncodedString(),
            ]
        }

        var payload: [String: Any] = [
            "title": composedTitle(),
            "category": category.rawValue,
            "rating": rating,
            "message": messageText.trimmingCharacters(in: .whitespacesAndNewlines),
            "content": "**\(composedTitle())**\n\(composedMarkdownBody())",
            "diagnostics": includeDiagnostics ? NEELxConfig.diagnosticsMarkdown() : "Omitted",
        ]
        if !encodedAttachments.isEmpty {
            payload["attachments"] = encodedAttachments
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                submitFailed = false
                submitResult = screenshots.isEmpty
                    ? "Feedback sent directly — thank you for helping improve NEELx!"
                    : "Feedback + \(screenshots.count) screenshot(s) sent — thank you!"
                messageText = ""
                titleText = ""
                screenshots.removeAll()
            } else {
                submitFailed = true
                submitResult = "Couldn't reach feedback server — use Email or GitHub Issue instead."
            }
        } catch {
            submitFailed = true
            submitResult = "Network error: \(error.localizedDescription)"
        }
    }
}

/// Lightweight floating window controller so testers can open Feedback from the Menu Bar too.
@MainActor
final class FeedbackWindowController {
    static let shared = FeedbackWindowController()
    private var window: NSWindow?

    private init() {}

    func present() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: FeedbackSheetView { [weak self] in
            self?.window?.close()
        })
        let win = NSWindow(contentViewController: hosting)
        win.title = "Send Feedback — NEELx"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}
