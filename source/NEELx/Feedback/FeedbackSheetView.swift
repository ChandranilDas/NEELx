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

enum EmailLaunchKind: Hashable {
    case appleMail
    case nativeMailto
    case gmailWebApp
    case outlookWebApp
    case yahooWebApp
    case genericWebApp
}

struct InstalledEmailApp: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let appURL: URL
    let bundleID: String
    let launchKind: EmailLaunchKind
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

    private static let knownNativeMailBundleIDs: Set<String> = [
        "com.apple.mail",
        "com.microsoft.Outlook",
        "com.readdle.smartemail-Mac",
        "com.readdle.SparkDesktop",
        "com.readdle.SparkDesktop.appstore",
        "org.mozilla.thunderbird",
        "com.mimestream.Mimestream",
        "it.bloop.airmail2",
        "io.canarymail.mac",
        "com.edisonmail.edisonmail",
        "ch.protonmail.desktop",
        "com.superhuman.mail",
        "com.postbox-inc.postbox",
        "com.emclient.mail.client",
        "com.freron.MailMate",
        "com.hey.app.desktop",
        "com.spike.mac",
    ]

    static func installedDesktopApps() -> [InstalledEmailApp] {
        var seenPaths = Set<String>()
        var seenBundleIDs = Set<String>()
        var apps: [InstalledEmailApp] = []

        func register(_ app: InstalledEmailApp) {
            let stdPath = app.appURL.standardizedFileURL.path
            guard !seenPaths.contains(stdPath), !seenBundleIDs.contains(app.bundleID) else { return }
            seenPaths.insert(stdPath)
            seenBundleIDs.insert(app.bundleID)
            apps.append(app)
        }

        // 1. Discover every native desktop app registered for `mailto:` (excluding bare web browsers)
        if let probe = URL(string: "mailto:support@example.com") {
            for url in NSWorkspace.shared.urlsForApplications(toOpen: probe) {
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier ?? url.path
                if excludedBrowserBundleIDs.contains(bundleID) { continue }
                let displayName = appDisplayName(bundle: bundle, url: url)
                let kind: EmailLaunchKind = (bundleID == "com.apple.mail") ? .appleMail : .nativeMailto
                let subtitle = (bundleID == "com.apple.mail") ? "Built-in macOS Mail" : "Installed Email App"
                register(InstalledEmailApp(
                    id: bundleID,
                    name: displayName,
                    subtitle: subtitle,
                    appURL: url,
                    bundleID: bundleID,
                    launchKind: kind
                ))
            }
        }

        // 2. Discover installed Email Web Apps (macOS Safari Web Apps + Chrome/Brave/Edge PWAs)
        //    and third-party desktop mail apps in /Applications & ~/Applications
        let home = FileManager.default.homeDirectoryForCurrentUser
        let searchDirs: [URL] = [
            home.appendingPathComponent("Applications", isDirectory: true),
            home.appendingPathComponent("Applications/Chrome Apps.localized", isDirectory: true),
            home.appendingPathComponent("Applications/Brave Browser Apps.localized", isDirectory: true),
            home.appendingPathComponent("Applications/Edge Apps.localized", isDirectory: true),
            home.appendingPathComponent("Applications/Chromium Apps.localized", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
        ]

        for dir in searchDirs {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in items where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier ?? url.path
                if excludedBrowserBundleIDs.contains(bundleID) { continue }

                let info = bundle?.infoDictionary ?? [:]
                let displayName = appDisplayName(bundle: bundle, url: url)
                let lowerName = displayName.lowercased()

                // Inspect Safari Web App Manifest (`start_url`) or Chromium PWA (`CrAppModeShortcutURL`)
                let manifest = info["Manifest"] as? [String: Any]
                let startURL = ((manifest?["start_url"] as? String)
                    ?? (info["CrAppModeShortcutURL"] as? String)
                    ?? "").lowercased()

                if startURL.contains("mail.google.com") || lowerName == "gmail" {
                    register(InstalledEmailApp(
                        id: bundleID,
                        name: displayName,
                        subtitle: "Installed Mail App",
                        appURL: url,
                        bundleID: bundleID,
                        launchKind: .gmailWebApp
                    ))
                } else if startURL.contains("outlook.live.com") || startURL.contains("outlook.office") || lowerName.contains("outlook") {
                    let isWebApp = !startURL.isEmpty || bundleID.contains("Safari.WebApp") || bundleID.contains(".app.")
                    register(InstalledEmailApp(
                        id: bundleID,
                        name: displayName,
                        subtitle: "Installed Mail App",
                        appURL: url,
                        bundleID: bundleID,
                        launchKind: isWebApp ? .outlookWebApp : .nativeMailto
                    ))
                } else if startURL.contains("mail.yahoo.com") || lowerName.contains("yahoo mail") {
                    register(InstalledEmailApp(
                        id: bundleID,
                        name: displayName,
                        subtitle: "Installed Mail App",
                        appURL: url,
                        bundleID: bundleID,
                        launchKind: .yahooWebApp
                    ))
                } else if knownNativeMailBundleIDs.contains(bundleID) {
                    let kind: EmailLaunchKind = (bundleID == "com.apple.mail") ? .appleMail : .nativeMailto
                    register(InstalledEmailApp(
                        id: bundleID,
                        name: displayName,
                        subtitle: kind == .appleMail ? "Built-in macOS Mail" : "Installed Email App",
                        appURL: url,
                        bundleID: bundleID,
                        launchKind: kind
                    ))
                } else if !startURL.isEmpty && (
                    startURL.contains("mail.proton") ||
                    startURL.contains("fastmail.com") ||
                    startURL.contains("mail.zoho") ||
                    startURL.contains("webmail") ||
                    startURL.contains("icloud.com/mail") ||
                    lowerName.contains("mail")
                ) {
                    register(InstalledEmailApp(
                        id: bundleID,
                        name: displayName,
                        subtitle: "Installed Webmail App",
                        appURL: url,
                        bundleID: bundleID,
                        launchKind: .genericWebApp
                    ))
                }
            }
        }

        // Prioritize user-installed email apps (Gmail, Outlook, Spark, etc.) FIRST, with Apple Mail below them
        return apps.sorted { a, b in
            if a.launchKind == .appleMail && b.launchKind != .appleMail { return false }
            if a.launchKind != .appleMail && b.launchKind == .appleMail { return true }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private static func appDisplayName(bundle: Bundle?, url: URL) -> String {
        (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
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
    @State private var showEmailAppPicker: Bool = false
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
                    Button {
                        installedMailApps = EmailAppCatalog.installedDesktopApps()
                        showEmailAppPicker.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Email")
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!canSubmit)
                    .popover(isPresented: $showEmailAppPicker, arrowEdge: .top) {
                        emailAppChooserPopover
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

    private var emailAppChooserPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose Email App")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 2)

            if !installedMailApps.isEmpty {
                ForEach(installedMailApps) { app in
                    Button {
                        showEmailAppPicker = false
                        openInDesktopMailApp(app)
                    } label: {
                        HStack(spacing: 9) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                                .resizable()
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(app.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .padding(.vertical, 2)
            }

            Text("Or Open Webmail in Browser")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            ForEach([
                ("Gmail (Web)", WebmailProvider.gmail),
                ("Outlook (Web)", WebmailProvider.outlook),
                ("Yahoo Mail (Web)", WebmailProvider.yahoo),
            ], id: \.0) { label, provider in
                Button {
                    showEmailAppPicker = false
                    openWebmail(provider)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "globe")
                            .frame(width: 22, height: 18)
                            .foregroundStyle(.secondary)
                        Text(label)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 255)
    }

    private func openInDesktopMailApp(_ app: InstalledEmailApp) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        switch app.launchKind {
        case .appleMail:
            // Apple Mail supports native NSSharingService with real image attachments + pre-filled To/Subject/Body
            if let service = NSSharingService(named: .composeEmail) {
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

        case .gmailWebApp:
            if let url = webmailComposeURL(for: .gmail) {
                copyFirstScreenshotToClipboardIfNeeded()
                NSWorkspace.shared.open([url], withApplicationAt: app.appURL, configuration: config) { _, error in
                    Task { @MainActor in
                        if error != nil {
                            NSWorkspace.shared.open(url)
                        }
                        submitFailed = false
                        submitResult = screenshots.isEmpty
                            ? "Opened pre-filled draft in \(app.name) — review and press Send!"
                            : "Opened \(app.name) — press Cmd+V inside the email to paste your screenshot (or use 'Send Directly' to auto-attach all \(screenshots.count))."
                    }
                }
                return
            }

        case .outlookWebApp:
            if let url = webmailComposeURL(for: .outlook) {
                copyFirstScreenshotToClipboardIfNeeded()
                NSWorkspace.shared.open([url], withApplicationAt: app.appURL, configuration: config) { _, error in
                    Task { @MainActor in
                        if error != nil { NSWorkspace.shared.open(url) }
                        submitFailed = false
                        submitResult = screenshots.isEmpty
                            ? "Opened pre-filled draft in \(app.name) — review and press Send!"
                            : "Opened \(app.name) — press Cmd+V inside the email to paste your screenshot (or use 'Send Directly' to auto-attach all \(screenshots.count))."
                    }
                }
                return
            }

        case .yahooWebApp:
            if let url = webmailComposeURL(for: .yahoo) {
                copyFirstScreenshotToClipboardIfNeeded()
                NSWorkspace.shared.open([url], withApplicationAt: app.appURL, configuration: config) { _, error in
                    Task { @MainActor in
                        if error != nil { NSWorkspace.shared.open(url) }
                        submitFailed = false
                        submitResult = screenshots.isEmpty
                            ? "Opened pre-filled draft in \(app.name) — review and press Send!"
                            : "Opened \(app.name) — press Cmd+V inside the email to paste your screenshot (or use 'Send Directly' to auto-attach all \(screenshots.count))."
                    }
                }
                return
            }

        case .genericWebApp:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                "To: \(NEELxConfig.feedbackEmail)\nSubject: \(composedTitle())\n\n\(composedPlainEmailBody())",
                forType: .string
            )
            NSWorkspace.shared.openApplication(at: app.appURL, configuration: config) { _, _ in
                Task { @MainActor in
                    submitFailed = false
                    submitResult = "Opened \(app.name) and copied your draft to clipboard — paste & Send!"
                }
            }
            return

        case .nativeMailto:
            break
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

    private func webmailComposeURL(for provider: WebmailProvider) -> URL? {
        let to = NEELxConfig.feedbackEmail
        let subject = composedTitle()
        let body = composedPlainEmailBody()

        var components: URLComponents
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
        case .outlook:
            components = URLComponents(string: "https://outlook.live.com/mail/0/deeplink/compose")!
            components.queryItems = [
                URLQueryItem(name: "to", value: to),
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: body),
            ]
        case .yahoo:
            components = URLComponents(string: "https://compose.mail.yahoo.com/")!
            components.queryItems = [
                URLQueryItem(name: "to", value: to),
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: body),
            ]
        }
        return components.url
    }

    /// Webmail compose URLs (Gmail/Outlook/Yahoo) cannot receive image attachments via query parameters,
    /// so we copy the attached screenshot onto the clipboard so a single Cmd+V pastes it straight into the draft.
    private func copyFirstScreenshotToClipboardIfNeeded() {
        guard let first = screenshots.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([first.preview])
    }

    private func openWebmail(_ provider: WebmailProvider) {
        let label: String
        switch provider {
        case .gmail: label = "Gmail"
        case .outlook: label = "Outlook Web"
        case .yahoo: label = "Yahoo Mail"
        }

        if let url = webmailComposeURL(for: provider) {
            copyFirstScreenshotToClipboardIfNeeded()
            NSWorkspace.shared.open(url)
            submitFailed = false
            submitResult = screenshots.isEmpty
                ? "Opened pre-filled draft in \(label) — press Send!"
                : "Opened \(label) — press Cmd+V inside the email to paste your screenshot (or click 'Send Directly' to auto-attach all \(screenshots.count))."
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
