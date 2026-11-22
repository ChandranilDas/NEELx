//
//  SecurityAuditLog.swift
//  NEELx
//
//  Privacy-first encrypted local audit log for unlock events, blocked wrong-face
//  attempts, and defeated spoof attacks. Persisted encrypted with AES-256-GCM under
//  the Touch-ID-gated session key (`~/Library/Application Support/NEELx/security-audit.enc`).
//

import AppKit
import CoreGraphics
import Foundation
import Observation

enum SecurityAuditKind: String, Codable, Sendable {
    case unlocked
    case faceRecognized
    case wrongFace
    case spoofBlocked
    case systemError

    var title: String {
        switch self {
        case .unlocked:       return "Unlocked"
        case .faceRecognized: return "Face recognized"
        case .wrongFace:      return "Unrecognized face"
        case .spoofBlocked:   return "Spoof blocked"
        case .systemError:    return "Unlock blocked"
        }
    }

    var systemImage: String {
        switch self {
        case .unlocked:       return "checkmark.shield.fill"
        case .faceRecognized: return "person.crop.circle.badge.checkmark"
        case .wrongFace:      return "person.crop.circle.badge.exclamationmark"
        case .spoofBlocked:   return "exclamationmark.shield.fill"
        case .systemError:    return "exclamationmark.triangle.fill"
        }
    }
}

struct SecurityAuditEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: SecurityAuditKind
    let detail: String
    /// Optional small JPEG thumbnail of a blocked intruder/spoof frame, encrypted inside the audit vault.
    let snapshotJPEG: Data?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: SecurityAuditKind,
        detail: String,
        snapshotJPEG: Data? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.detail = detail
        self.snapshotJPEG = snapshotJPEG
    }
}

@Observable
@MainActor
final class SecurityAuditLog {
    static let shared = SecurityAuditLog()

    private(set) var entries: [SecurityAuditEntry] = []
    private let maxEntries = 50

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("NEELx", isDirectory: true)
            .appendingPathComponent("security-audit.enc")
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: .secureCredentialSessionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadIfUnlocked()
            }
        }
        reloadIfUnlocked()
    }

    func reloadIfUnlocked() {
        guard SecureCredentialManager.isSessionUnlocked else {
            entries = []
            return
        }
        guard let ciphertext = try? Data(contentsOf: Self.storageURL),
              let plaintext = try? SecureCredentialManager.decrypt(ciphertext),
              let decoded = try? JSONDecoder().decode([SecurityAuditEntry].self, from: plaintext) else {
            entries = []
            return
        }
        entries = decoded
    }

    func record(kind: SecurityAuditKind, detail: String, snapshotImage: CGImage? = nil) {
        guard NEELxSettings.shared.intruderLogEnabled else { return }
        guard SecureCredentialManager.isSessionUnlocked else { return }

        // Only attach compact JPEG thumbnails for blocked intruders/spoofs (never for normal unlocks)
        let jpeg: Data? = (kind != .unlocked) ? snapshotImage.flatMap(Self.encodeThumbnailJPEG) : nil
        let entry = SecurityAuditEntry(kind: kind, detail: detail, snapshotJPEG: jpeg)

        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        persist()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: Self.storageURL)
    }

    private func persist() {
        guard SecureCredentialManager.isSessionUnlocked else { return }
        guard let plaintext = try? JSONEncoder().encode(entries),
              let ciphertext = try? SecureCredentialManager.encrypt(plaintext) else { return }

        let dir = Self.storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? ciphertext.write(to: Self.storageURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.storageURL.path)
    }

    private static func encodeThumbnailJPEG(_ cgImage: CGImage) -> Data? {
        let maxSide = 220
        let scale = min(Double(maxSide) / Double(max(cgImage.width, 1)), Double(maxSide) / Double(max(cgImage.height, 1)), 1.0)
        let w = max(Int(Double(cgImage.width) * scale), 16)
        let h = max(Int(Double(cgImage.height) * scale), 16)

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: scaled)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.65])
    }
}
