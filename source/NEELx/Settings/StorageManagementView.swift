//
//  StorageManagementView.swift
//  NEELx
//
//  Item #58: Storage Management for Models & Cache — In-app inspection and breakdown
//  of neural model weights, encrypted biometric vaults, and temporary cache buffers
//  with 1-click cleanup actions.
//

import SwiftUI

struct StorageItem: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let sizeBytes: Int64
    let pathDescription: String
    let systemImage: String
    let isRemovable: Bool
}

@Observable
@MainActor
final class StorageInspector {
    static let shared = StorageInspector()

    private(set) var items: [StorageItem] = []
    private(set) var isScanning = false

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    private init() {
        refresh()
    }

    func refresh() {
        isScanning = true
        var discovered: [StorageItem] = []

        // 1. ArcFace 512-D Neural Recognition Model (Bundled/Local)
        var arcFaceBytes: Int64 = 0
        if let bundleModel = Bundle.main.url(forResource: "ArcFace", withExtension: "mlmodelc") {
            arcFaceBytes = Self.folderSize(url: bundleModel)
        } else {
            let localDev = URL(fileURLWithPath: "source/NEELx/Models/ArcFace.mlpackage")
            if FileManager.default.fileExists(atPath: localDev.path) {
                arcFaceBytes = Self.folderSize(url: localDev)
            }
        }
        if arcFaceBytes == 0 { arcFaceBytes = 12_580_000 } // ~12.5 MB baseline
        discovered.append(StorageItem(
            name: "ArcFace 512-D Face Recognition",
            category: "Neural Network (ANE)",
            sizeBytes: arcFaceBytes,
            pathDescription: "Bundled Apple Silicon Core ML neural weights",
            systemImage: "brain.head.profile",
            isRemovable: false
        ))

        // 2. Depth Anything V2 Small Float16 Neural Depth Engine
        var depthBytes: Int64 = 0
        let downloadedURL = NeuralDepthAnalyzer.downloadedModelURL
        if FileManager.default.fileExists(atPath: downloadedURL.path) {
            depthBytes = Self.folderSize(url: downloadedURL)
        } else if let bundled = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc") {
            depthBytes = Self.folderSize(url: bundled)
        } else {
            let localDev = URL(fileURLWithPath: "source/NEELx/Models/DepthAnythingV2SmallF16.mlpackage")
            if FileManager.default.fileExists(atPath: localDev.path) {
                depthBytes = Self.folderSize(url: localDev)
            }
        }
        if depthBytes == 0 { depthBytes = 47_450_000 } // ~47.5 MB
        discovered.append(StorageItem(
            name: "Depth Anything V2 3D Anti-Spoofing",
            category: "Neural Network (ANE)",
            sizeBytes: depthBytes,
            pathDescription: "Apple Silicon ANE 3D topological relief model",
            systemImage: "cube.transparent",
            isRemovable: false
        ))

        // 3. Encrypted Local Audit & Security Vault
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let auditURL = appSupport.appendingPathComponent("NEELx", isDirectory: true).appendingPathComponent("security-audit.enc")
        var auditBytes: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: auditURL.path),
           let size = attrs[.size] as? Int64 {
            auditBytes = size
        }
        discovered.append(StorageItem(
            name: "Encrypted Security Audit Vault",
            category: "Local Vault (AES-256)",
            sizeBytes: auditBytes,
            pathDescription: "Touch-ID-gated audit logs & optional failure thumbnails",
            systemImage: "lock.shield",
            isRemovable: true
        ))

        // 4. Temporary Compiler & Download Buffers
        let tempDir = FileManager.default.temporaryDirectory
        var tempBytes: Int64 = 0
        if let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in contents where file.lastPathComponent.hasPrefix("NEELx-") {
                tempBytes += Self.folderSize(url: file)
            }
        }
        discovered.append(StorageItem(
            name: "Temporary Download & Compiler Cache",
            category: "Caches",
            sizeBytes: tempBytes,
            pathDescription: "Transient model download chunks & temporary scratch buffers",
            systemImage: "arrow.triangle.2.circlepath",
            isRemovable: true
        ))

        self.items = discovered
        self.isScanning = false
    }

    func cleanTemporaryCachesAndSnapshots() {
        // 1. Purge all photo thumbnails from the audit log
        SecurityAuditLog.shared.clearAllSnapshots()

        // 2. Remove all temporary NEELx scratch buffers
        let tempDir = FileManager.default.temporaryDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in contents where file.lastPathComponent.hasPrefix("NEELx-") {
                try? FileManager.default.removeItem(at: file)
            }
        }

        refresh()
    }

    private static func folderSize(url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = attrs.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

struct StorageManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inspector = StorageInspector.shared
    @State private var didClean = false

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Storage & Cache Management")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Breakdown of neural weights, encrypted biometric storage, and caches.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // Total storage banner
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "internaldrive")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Disk Space Allocated")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(Self.byteFormatter.string(fromByteCount: inspector.totalBytes))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }

                Spacer()

                Button {
                    inspector.cleanTemporaryCachesAndSnapshots()
                    didClean = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        didClean = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: didClean ? "checkmark" : "trash")
                        Text(didClean ? "Cleaned!" : "Clean Caches & Snapshots")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            // Itemized Breakdown
            VStack(spacing: 8) {
                ForEach(inspector.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(item.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                Text(item.category)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.pathDescription)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(Self.byteFormatter.string(fromByteCount: item.sizeBytes))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.04)))
                }
            }

            Spacer()

            HStack {
                Text("NEELx keeps neural models on local Apple Silicon storage for instant zero-latency offline verification.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .controlSize(.regular)
            }
        }
        .padding(20)
        .frame(width: 540, height: 420)
        .onAppear {
            inspector.refresh()
        }
    }
}
