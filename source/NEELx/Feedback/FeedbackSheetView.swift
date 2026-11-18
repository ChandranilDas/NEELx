//
//  FeedbackSheetView.swift
//  NEELx
//
//  Native SwiftUI feedback & bug-reporting sheet for open-source / beta testers.
//  Supports 1-click direct webhook submission (Formspree/Discord/custom), pre-filled
//  GitHub Issues, Mail, and clipboard export — with automatic privacy-scrubbed Mac diagnostics.
//

import AppKit
import SwiftUI

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

struct FeedbackSheetView: View {
    var onDismiss: () -> Void

    @State private var category: FeedbackCategory = .experience
    @State private var rating: Int = 5
    @State private var titleText: String = ""
    @State private var messageText: String = ""
    @State private var includeDiagnostics: Bool = true
    @State private var isSubmitting: Bool = false
    @State private var submitResult: String?
    @State private var submitFailed: Bool = false
    @State private var didCopy: Bool = false

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
                    Text("Help shape NEELx — bug reports, unlock speed notes, and feature ideas go straight to the developer.")
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
                    .frame(height: 115)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
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
                    Button("Email") { openEmailComposer() }
                        .disabled(!canSubmit)
                }

                Spacer()

                Button("GitHub Issue") { openPreFilledGitHubIssue() }
                    .disabled(!canSubmit)

                if hasWebhook {
                    Button(isSubmitting ? "Sending…" : "Send Directly") {
                        Task { await submitToWebhook() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                }
            }
        }
        .padding(20)
        .frame(width: 470)
    }

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

    private func openEmailComposer() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = NEELxConfig.feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: composedTitle()),
            URLQueryItem(name: "body", value: composedMarkdownBody()),
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
            submitFailed = false
            submitResult = "Opened Mail draft — thank you!"
        }
    }

    private func submitToWebhook() async {
        guard let url = URL(string: NEELxConfig.feedbackWebhookURL) else { return }
        isSubmitting = true
        submitResult = nil
        submitFailed = false
        defer { isSubmitting = false }

        let payload: [String: Any] = [
            "title": composedTitle(),
            "category": category.rawValue,
            "rating": rating,
            "message": messageText.trimmingCharacters(in: .whitespacesAndNewlines),
            "content": "**\(composedTitle())**\n\(composedMarkdownBody())", // Discord-compatible key
            "diagnostics": includeDiagnostics ? NEELxConfig.diagnosticsMarkdown() : "Omitted",
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                submitFailed = false
                submitResult = "Feedback sent — thank you for helping improve NEELx!"
                messageText = ""
                titleText = ""
            } else {
                submitFailed = true
                submitResult = "Couldn't reach feedback server — use GitHub Issue or Copy Report instead."
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
