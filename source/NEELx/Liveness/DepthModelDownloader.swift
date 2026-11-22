//
//  DepthModelDownloader.swift
//  NEELx
//
//  One-click in-app downloader & on-device Core ML compiler for Apple's official
//  DepthAnythingV2SmallF16 model (47.5 MB). Uses native URLSessionDownloadTask
//  streaming for full-speed downloads (~3s on Wi-Fi, near-zero CPU) and compiles
//  natively via `MLModel.compileModel(at:)` with zero Xcode required.
//

import CoreML
import CryptoKit
import Foundation
import Observation

/// High-speed native URLSession download helper with smooth progress callbacks.
nonisolated final class FastFileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var onProgress: (@Sendable (Int64, Int64) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    func download(
        from url: URL,
        userAgent: String = "NEELx/2.0",
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        self.onProgress = onProgress
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 1800
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                let downloadTask = session.downloadTask(with: request)
                self.task = downloadTask
                downloadTask.resume()
            }
        } onCancel: {
            self.task?.cancel()
            self.session?.invalidateAndCancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let err = NSError(
                domain: "NEELx.Downloader",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))."]
            )
            continuation?.resume(throwing: err)
            continuation = nil
            session.finishTasksAndInvalidate()
            return
        }

        // Move out of URLSession's ephemeral location before this delegate method returns
        let preserved = FileManager.default.temporaryDirectory
            .appendingPathComponent("NEELx-dl-\(UUID().uuidString).tmp")
        do {
            try FileManager.default.moveItem(at: location, to: preserved)
            continuation?.resume(returning: preserved)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            session.finishTasksAndInvalidate()
        }
    }
}

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

    // Pinned commit revision & checksums for supply-chain integrity (Item #5)
    private let baseURL = "https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/cfef6f6f2a70783dedc0bfae40cecbc2052285d3/DepthAnythingV2SmallF16.mlpackage"
    private let files: [(relPath: String, approxBytes: Double, expectedSHA256: String)] = [
        ("Manifest.json", 1_024, "2883ae290c48fe916dc5ececac03a7d847fa277165a49ef5652fa1d2b9cb55f7"),
        ("Data/com.apple.CoreML/model.mlmodel", 400_000, "44ac97a3efcfd52113183fb2862ff59cd0368e9ec2e30a90a54980dd11407042"),
        ("Data/com.apple.CoreML/weights/weight.bin", 49_420_000, "fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed"),
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

                let baseCompleted = completedBeforeFile
                let downloader = FastFileDownloader()
                let downloadedTemp = try await downloader.download(from: url) { [weak self] written, expected in
                    let overall = min((baseCompleted + Double(written)) / max(totalApprox, 1), 0.96)
                    let mbDone = (baseCompleted + Double(written)) / (1024 * 1024)
                    let mbTotal = totalApprox / (1024 * 1024)
                    Task { @MainActor [weak self] in
                        self?.state = .downloading(
                            progress: overall,
                            status: String(format: "Downloading 3D Depth Engine… %.1f / %.1f MB", mbDone, mbTotal)
                        )
                    }
                }

                // Verify cryptographic checksum (Item #5)
                if let actualHash = Self.computeSHA256(url: downloadedTemp),
                   actualHash.lowercased() != item.expectedSHA256.lowercased() {
                    try? fm.removeItem(at: downloadedTemp)
                    throw NSError(
                        domain: "NEELx.Downloader",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Cryptographic checksum mismatch for \(item.relPath). Expected \(item.expectedSHA256), got \(actualHash)"]
                    )
                }

                if fm.fileExists(atPath: destFile.path) {
                    try fm.removeItem(at: destFile)
                }
                try fm.moveItem(at: downloadedTemp, to: destFile)

                let actualSize = (try? fm.attributesOfItem(atPath: destFile.path)[.size] as? Double) ?? item.approxBytes
                completedBeforeFile += actualSize
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

    private static func computeSHA256(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 512)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
