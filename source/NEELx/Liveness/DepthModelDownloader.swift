//
//  DepthModelDownloader.swift
//  NEELx
//
//  One-click in-app downloader & on-device Core ML compiler for Apple's official
//  DepthAnythingV2SmallF16 model (47.5 MB). Lets beta testers download a lightweight
//  ~15 MB DMG and enable Stage 3 Neural 3D Depth right inside Settings with zero Xcode
//  or Terminal commands required.
//

import CoreML
import Foundation
import Observation

@Observable
@MainActor
final class DepthModelDownloader {
    static let shared = DepthModelDownloader()

    enum State: Equatable {
        case idle
        case downloading(progress: Double, status: String)
        case compiling
        case installed
        case failed(String)
    }

    private(set) var state: State = NeuralDepthAnalyzer.shared.isModelAvailable ? .installed : .idle
    private var downloadTask: Task<Void, Never>?

    private let baseURL = "https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/main/DepthAnythingV2SmallF16.mlpackage"
    private let files: [(relPath: String, approxBytes: Double)] = [
        ("Manifest.json", 1_024),
        ("Data/com.apple.CoreML/model.mlmodel", 400_000),
        ("Data/com.apple.CoreML/weights/weight.bin", 49_420_000),
    ]

    private init() {}

    func refreshState() {
        if NeuralDepthAnalyzer.shared.isModelAvailable {
            state = .installed
        } else if case .installed = state {
            state = .idle
        }
    }

    func startDownload() {
        guard downloadTask == nil else { return }
        if NeuralDepthAnalyzer.shared.isModelAvailable {
            state = .installed
            return
        }

        state = .downloading(progress: 0.02, status: "Connecting to Apple Core ML repository…")
        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer { self.downloadTask = nil }
            await self.performDownloadAndCompile()
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        state = NeuralDepthAnalyzer.shared.isModelAvailable ? .installed : .idle
    }

    private func performDownloadAndCompile() async {
        let fm = FileManager.default
        let tempPackage = fm.temporaryDirectory
            .appendingPathComponent("NEELx-DepthDownload-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("DepthAnythingV2SmallF16.mlpackage", isDirectory: true)

        defer {
            try? fm.removeItem(at: tempPackage.deletingLastPathComponent())
        }

        do {
            try fm.createDirectory(at: tempPackage, withIntermediateDirectories: true)

            let totalApprox = files.reduce(0.0) { $0 + $1.approxBytes }
            var completedBeforeFile = 0.0

            for (index, item) in files.enumerated() {
                try Task.checkCancellation()
                guard let url = URL(string: "\(baseURL)/\(item.relPath)") else { continue }
                let destFile = tempPackage.appendingPathComponent(item.relPath)
                try fm.createDirectory(at: destFile.deletingLastPathComponent(), withIntermediateDirectories: true)

                var request = URLRequest(url: url)
                request.setValue("NEELx/2.0", forHTTPHeaderField: "User-Agent")

                let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw NSError(
                        domain: "NEELx.DepthModelDownloader",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))."]
                    )
                }

                let expectedLen = Double(response.expectedContentLength > 0 ? response.expectedContentLength : Int64(item.approxBytes))
                fm.createFile(atPath: destFile.path, contents: nil)
                let handle = try FileHandle(forWritingTo: destFile)
                defer { try? handle.close() }

                var buffer = Data()
                buffer.reserveCapacity(256 * 1024)
                var receivedForFile = 0.0
                var lastUIUpdate = CFAbsoluteTimeGetCurrent()

                for try await byte in asyncBytes {
                    try Task.checkCancellation()
                    buffer.append(byte)
                    if buffer.count >= 128 * 1024 {
                        try handle.write(contentsOf: buffer)
                        receivedForFile += Double(buffer.count)
                        buffer.removeAll(keepingCapacity: true)

                        let now = CFAbsoluteTimeGetCurrent()
                        if now - lastUIUpdate >= 0.12 {
                            lastUIUpdate = now
                            let overall = min((completedBeforeFile + receivedForFile) / max(totalApprox, 1), 0.96)
                            let mbDone = (completedBeforeFile + receivedForFile) / (1024 * 1024)
                            let mbTotal = totalApprox / (1024 * 1024)
                            state = .downloading(
                                progress: overall,
                                status: String(format: "Downloading 3D Depth Engine… %.1f / %.1f MB", mbDone, mbTotal)
                            )
                        }
                    }
                }
                if !buffer.isEmpty {
                    try handle.write(contentsOf: buffer)
                    receivedForFile += Double(buffer.count)
                }
                completedBeforeFile += max(receivedForFile, expectedLen)
                let pct = min(completedBeforeFile / max(totalApprox, 1), 0.98)
                state = .downloading(progress: pct, status: "Downloaded file \(index + 1) of \(files.count)…")
            }

            try Task.checkCancellation()
            state = .compiling

            // Compile .mlpackage -> .mlmodelc natively on-device (no Xcode required!)
            let compiledTempURL = try await Task.detached(priority: .userInitiated) {
                try MLModel.compileModel(at: tempPackage)
            }.value

            let finalURL = NeuralDepthAnalyzer.downloadedModelURL
            try fm.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: finalURL.path) {
                try fm.removeItem(at: finalURL)
            }
            try fm.moveItem(at: compiledTempURL, to: finalURL)

            await Task.detached(priority: .userInitiated) {
                NeuralDepthAnalyzer.shared.reloadModel()
            }.value

            NEELxSettings.shared.neuralDepthEnabled = true
            state = .installed
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
