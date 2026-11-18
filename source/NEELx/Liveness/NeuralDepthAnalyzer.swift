//
//  NeuralDepthAnalyzer.swift
//  NEELx
//
//  Stage 3 Neural 3D Depth Anti-Spoofing powered by Apple's Core ML
//  DepthAnythingV2SmallF16 running on the Apple Neural Engine (ANE).
//
//  Distinguishes real 3D human faces from 2D photos/screens by fitting a
//  least-squares 2D plane to the face region and measuring:
//    1. Nose protrusion above the facial cheek/eye plane
//    2. Non-planar 3D surface curvature (plane-fit RMSE residual)
//    3. Inference latency & model availability (gracefully abstains if unbundled)
//

import CoreML
import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Per-frame 3D neural depth analysis result inside the detected face oval.
nonisolated struct NeuralDepthReading: Equatable, Sendable {
    /// How much the central nose protrudes closer than the best-fit cheek/perimeter plane,
    /// normalized by local facial/scene depth scale (positive = nose closer than cheeks/perimeter).
    let noseProtrusion: Float
    /// Normalized RMSE residual from fitting a flat 2D plane z = a*x + b*y + c to the inner face oval.
    let planarityResidual: Float
    /// Depth cliff between the face and the room immediately outside the left/right head silhouette (0...1+).
    /// High on a real 3D head in front of a room; near zero when the face sits coplanar on a flat screen/page.
    let backgroundCliff: Float
    /// Overall 0...1 confidence that the face is a genuine 3D surface (higher = more 3D).
    let depth3DScore: Float
    /// Overall 0...1 confidence that the face is a flat 2D spoof plane (higher = flatter/more suspicious).
    let flatSpoofScore: Float
    /// L2-normalized 9-zone (3x3) tilt-invariant 3D facial relief vector (plane-subtracted),
    /// stored during enrollment and compared at unlock for personalized 3D depth matching.
    let depthSignature: [Float]
    /// Wall-clock ANE inference time in milliseconds.
    let inferenceMs: Double
}

/// Optional live colorized 3D depth heatmap image for Face Lab visualization.
nonisolated struct NeuralDepthHeatmapResult: @unchecked Sendable {
    let reading: NeuralDepthReading
    let heatmapImage: CGImage?
}

nonisolated final class NeuralDepthAnalyzer: @unchecked Sendable {
    static let shared = NeuralDepthAnalyzer()

    private let lock = NSLock()
    private var model: MLModel?
    private var pixelBufferPool: CVPixelBufferPool?
    private var inputName: String = "image"
    private var outputName: String = "depth"
    private var inputWidth: Int = 518
    private var inputHeight: Int = 392
    private var didAttemptLoad = false

    /// Instant bundle check — never blocks the main thread while ANE compilation is warming up.
    var isModelAvailable: Bool {
        Self.locateModel() != nil
    }

    private init() {}

    /// Lazily loads and compiles/warms the Core ML model on ANE. Safe to call from a background task.
    @discardableResult
    func warmUp() -> Bool {
        ensureLoaded(nonBlocking: false) != nil
    }

    /// Resets cached state after an in-app model download completes and warms the newly installed ANE model.
    func reloadModel() {
        lock.lock()
        model = nil
        pixelBufferPool = nil
        didAttemptLoad = false
        lock.unlock()
        _ = warmUp()
    }

    /// Where the optional in-app downloader installs the compiled Core ML model on lightweight beta builds.
    static var downloadedModelURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("NEELx", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("DepthAnythingV2SmallF16.mlmodelc", isDirectory: true)
    }

    private func ensureLoaded(nonBlocking: Bool) -> (MLModel, CVPixelBufferPool)? {
        if nonBlocking {
            guard lock.try() else { return nil }
        } else {
            lock.lock()
        }
        defer { lock.unlock() }

        if let model, let pool = pixelBufferPool {
            return (model, pool)
        }
        if didAttemptLoad { return nil }
        didAttemptLoad = true

        guard let modelURL = Self.locateModel() else { return nil }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        guard let loaded = try? MLModel(contentsOf: modelURL, configuration: config) else {
            return nil
        }

        // Dynamically read exact input/output schema from the Core ML model metadata
        if let (inName, inDesc) = loaded.modelDescription.inputDescriptionsByName.first {
            inputName = inName
            if let constraint = inDesc.imageConstraint {
                inputWidth = constraint.pixelsWide
                inputHeight = constraint.pixelsHigh
            }
        }
        if let (outName, _) = loaded.modelDescription.outputDescriptionsByName.first {
            outputName = outName
        }

        guard let pool = Self.makePixelBufferPool(width: inputWidth, height: inputHeight) else {
            return nil
        }

        model = loaded
        pixelBufferPool = pool
        return (loaded, pool)
    }

    private static func locateModel() -> URL? {
        for name in ["DepthAnythingV2SmallF16", "DepthAnythingV2"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                return url
            }
        }
        let downloaded = downloadedModelURL
        if FileManager.default.fileExists(atPath: downloaded.path) {
            return downloaded
        }
        return nil
    }

    private static func makePixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        return pool
    }

    /// Runs Depth Anything V2 on the full camera frame and analyzes 3D curvature + nose protrusion
    /// inside `normalizedFaceBox` (Vision bottom-left normalized coordinates, 0...1).
    /// Returns `nil` if the model isn't bundled or inference fails (caller gracefully abstains).
    func analyze(
        frame: CGImage,
        normalizedFaceBox: CGRect,
        noseNormalizedCenter: CGPoint? = nil
    ) -> NeuralDepthReading? {
        analyzeWithHeatmap(
            frame: frame,
            normalizedFaceBox: normalizedFaceBox,
            noseNormalizedCenter: noseNormalizedCenter,
            includeHeatmap: false
        )?.reading
    }

    /// Runs Depth Anything V2 and optionally renders a colorized Inferno-style 3D depth heatmap (for Face Lab).
    func analyzeWithHeatmap(
        frame: CGImage,
        normalizedFaceBox: CGRect,
        noseNormalizedCenter: CGPoint? = nil,
        includeHeatmap: Bool
    ) -> NeuralDepthHeatmapResult? {
        guard let (loadedModel, pool) = ensureLoaded(nonBlocking: true) else { return nil }

        let startTime = CFAbsoluteTimeGetCurrent()

        var pbOut: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pbOut)
        guard status == kCVReturnSuccess, let inputBuffer = pbOut else { return nil }

        guard Self.render(frame, into: inputBuffer, width: inputWidth, height: inputHeight) else {
            return nil
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(pixelBuffer: inputBuffer)
        ]),
        let prediction = try? loadedModel.prediction(from: provider),
        let depthBuffer = prediction.featureValue(for: outputName)?.imageBufferValue else {
            return nil
        }

        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        guard let reading = Self.evaluateDepthMap(
            depthBuffer,
            normalizedFaceBox: normalizedFaceBox,
            noseNormalizedCenter: noseNormalizedCenter,
            inferenceMs: elapsedMs
        ) else { return nil }

        let heatmap = includeHeatmap ? Self.renderHeatmap(from: depthBuffer) : nil
        return NeuralDepthHeatmapResult(reading: reading, heatmapImage: heatmap)
    }

    /// Renders a compact colorized Inferno-style 3D depth heatmap (`CGImage`) for live visualization in Face Lab.
    private static func renderHeatmap(from depthBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }
        let srcW = CVPixelBufferGetWidth(depthBuffer)
        let srcH = CVPixelBufferGetHeight(depthBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        let fmt = CVPixelBufferGetPixelFormatType(depthBuffer)

        // Downsample 2x for snappy 60fps UI display (~259x196)
        let dstW = max(srcW / 2, 1)
        let dstH = max(srcH / 2, 1)
        var values = [Float](repeating: 0, count: dstW * dstH)
        var minV: Float = .greatestFiniteMagnitude
        var maxV: Float = -.greatestFiniteMagnitude

        for y in 0..<dstH {
            let sy = min(y * 2, srcH - 1)
            let rowPtr = baseAddress.advanced(by: sy * bytesPerRow)
            for x in 0..<dstW {
                let sx = min(x * 2, srcW - 1)
                let v: Float
                switch fmt {
                case kCVPixelFormatType_OneComponent16Half:
                    v = Self.readHalfFloat(rowPtr, index: sx)
                case kCVPixelFormatType_OneComponent32Float:
                    v = rowPtr.assumingMemoryBound(to: Float.self)[sx]
                default:
                    v = Float(rowPtr.assumingMemoryBound(to: UInt8.self)[sx]) / 255.0
                }
                let finiteV = v.isFinite ? v : 0
                values[y * dstW + x] = finiteV
                if finiteV < minV { minV = finiteV }
                if finiteV > maxV { maxV = finiteV }
            }
        }

        let span = max(maxV - minV, 1e-4)
        var rgba = [UInt8](repeating: 255, count: dstW * dstH * 4)
        for i in 0..<(dstW * dstH) {
            let t = clamp((values[i] - minV) / span, 0, 1)
            let (r, g, b) = infernoColor(t)
            let idx = i * 4
            rgba[idx + 0] = r
            rgba[idx + 1] = g
            rgba[idx + 2] = b
            rgba[idx + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: dstW * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// 5-stop Inferno colormap (deep indigo = far background → magenta → orange → warm yellow-white = closest nose).
    private static func infernoColor(_ t: Float) -> (UInt8, UInt8, UInt8) {
        let stops: [(Float, Float, Float, Float)] = [
            (0.00, 0.05, 0.03, 0.16),
            (0.25, 0.34, 0.06, 0.43),
            (0.50, 0.74, 0.21, 0.33),
            (0.75, 0.98, 0.55, 0.04),
            (1.00, 0.99, 0.98, 0.65),
        ]
        for i in 0..<(stops.count - 1) {
            let s0 = stops[i], s1 = stops[i + 1]
            if t >= s0.0 && t <= s1.0 {
                let f = (t - s0.0) / max(s1.0 - s0.0, 1e-4)
                let r = UInt8(clamp((s0.1 + f * (s1.1 - s0.1)) * 255, 0, 255))
                let g = UInt8(clamp((s0.2 + f * (s1.2 - s0.2)) * 255, 0, 255))
                let b = UInt8(clamp((s0.3 + f * (s1.3 - s0.3)) * 255, 0, 255))
                return (r, g, b)
            }
        }
        return (252, 250, 166)
    }

    private static func render(_ image: CGImage, into buffer: CVPixelBuffer, width: Int, height: Int) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return false }

        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }

    /// Reads the `OneComponent16Half` (`Float16`) depth map and computes 3D facial geometry metrics.
    /// Vision boxes use bottom-left origin; CVPixelBuffer uses top-left origin.
    private static func evaluateDepthMap(
        _ depthBuffer: CVPixelBuffer,
        normalizedFaceBox: CGRect,
        noseNormalizedCenter: CGPoint?,
        inferenceMs: Double
    ) -> NeuralDepthReading? {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthBuffer)

        func readDepth(x: Int, y: Int) -> Float {
            let cx = min(max(x, 0), width - 1)
            let cy = min(max(y, 0), height - 1)
            let rowPtr = baseAddress.advanced(by: cy * bytesPerRow)
            switch pixelFormat {
            case kCVPixelFormatType_OneComponent16Half:
                return Self.readHalfFloat(rowPtr, index: cx)
            case kCVPixelFormatType_OneComponent32Float:
                return rowPtr.assumingMemoryBound(to: Float.self)[cx]
            default:
                return Float(rowPtr.assumingMemoryBound(to: UInt8.self)[cx]) / 255.0
            }
        }

        // 1. Estimate robust global scene depth span (5th to 95th percentile on coarse 24x18 grid)
        var sceneSamples: [Float] = []
        sceneSamples.reserveCapacity(432)
        for gy in 0..<18 {
            let py = Int((Double(gy) + 0.5) / 18.0 * Double(height))
            for gx in 0..<24 {
                let px = Int((Double(gx) + 0.5) / 24.0 * Double(width))
                let v = readDepth(x: px, y: py)
                if v.isFinite { sceneSamples.append(v) }
            }
        }
        guard sceneSamples.count >= 100 else { return nil }
        sceneSamples.sort()
        let p05 = sceneSamples[Int(Double(sceneSamples.count) * 0.05)]
        let p95 = sceneSamples[Int(Double(sceneSamples.count) * 0.95)]
        let sceneSpan = max(p95 - p05, 1e-3)

        // 2. Convert Vision bottom-left box to top-left pixel coordinates, inset slightly into the face oval
        // so background pixels behind the ears/hair never contaminate the facial plane fit.
        let insetX = normalizedFaceBox.width * 0.14
        let insetY = normalizedFaceBox.height * 0.12
        let innerBox = normalizedFaceBox.insetBy(dx: insetX, dy: insetY)
        guard innerBox.width > 0.04, innerBox.height > 0.04 else { return nil }

        let xMin = Double(innerBox.minX) * Double(width)
        let xMax = Double(innerBox.maxX) * Double(width)
        // Flip Y: Vision maxY is top of face (smallest pixel y)
        let yMin = (1.0 - Double(innerBox.maxY)) * Double(height)
        let yMax = (1.0 - Double(innerBox.minY)) * Double(height)

        let boxW = xMax - xMin
        let boxH = yMax - yMin
        guard boxW >= 12, boxH >= 12 else { return nil }

        // 3. Sample a 12x12 elliptical grid inside the inner face oval for plane fitting
        struct Sample3D { let nx: Double; let ny: Double; let d: Double; let radiusSq: Double }
        var faceSamples: [Sample3D] = []
        faceSamples.reserveCapacity(144)

        let gridN = 12
        for gy in 0..<gridN {
            let v = (Double(gy) + 0.5) / Double(gridN)
            let dy = (v - 0.5) * 2.0 // -1...1
            let py = Int(yMin + v * boxH)
            for gx in 0..<gridN {
                let u = (Double(gx) + 0.5) / Double(gridN)
                let dx = (u - 0.5) * 2.0 // -1...1
                let rSq = dx * dx + dy * dy
                // Keep only points inside the inscribed ellipse of the face
                guard rSq <= 0.95 else { continue }
                let px = Int(xMin + u * boxW)
                let d = Double(readDepth(x: px, y: py))
                if d.isFinite {
                    faceSamples.append(Sample3D(nx: dx, ny: dy, d: d, radiusSq: rSq))
                }
            }
        }
        guard faceSamples.count >= 25 else { return nil }

        // Local face depth span prevents a deep background room from crushing real facial relief
        let sortedFaceDepths = faceSamples.map(\.d).sorted()
        let faceP05 = sortedFaceDepths[Int(Double(sortedFaceDepths.count) * 0.05)]
        let faceP95 = sortedFaceDepths[Int(Double(sortedFaceDepths.count) * 0.95)]
        let faceSpan = max(faceP95 - faceP05, 1e-4)
        let normScale = max(faceSpan, Double(sceneSpan) * 0.22)

        // 4. Fit least-squares plane d(nx, ny) = a*nx + b*ny + c to ALL oval points -> measures overall 3D curvature
        guard let fullPlane = fitPlane(faceSamples.map { ($0.nx, $0.ny, $0.d) }) else { return nil }

        var sqErrSum = 0.0
        var zoneSums = [Double](repeating: 0, count: 9)
        var zoneCounts = [Int](repeating: 0, count: 9)
        for s in faceSamples {
            let pred = fullPlane.a * s.nx + fullPlane.b * s.ny + fullPlane.c
            let err = s.d - pred
            sqErrSum += err * err

            // Bin plane-subtracted relief into 3x3 tilt-invariant facial zones (forehead, eyes, nose, cheeks, chin)
            let zx = min(max(Int(((s.nx + 1.0) * 0.5) * 3.0), 0), 2)
            let zy = min(max(Int(((s.ny + 1.0) * 0.5) * 3.0), 0), 2)
            let zi = zy * 3 + zx
            zoneSums[zi] += err / normScale
            zoneCounts[zi] += 1
        }
        let rmse = (sqErrSum / Double(faceSamples.count)).squareRoot()
        let planarityResidual = Float(rmse / normScale)

        // Build L2-normalized 9-zone 3D facial depth signature
        var rawSig = [Float](repeating: 0, count: 9)
        var normSq: Float = 0
        for i in 0..<9 {
            let v = zoneCounts[i] > 0 ? Float(zoneSums[i] / Double(zoneCounts[i])) : 0
            rawSig[i] = v
            normSq += v * v
        }
        let depthSignature: [Float]
        if normSq > 1e-8 {
            let invNorm = 1.0 / normSq.squareRoot()
            depthSignature = rawSig.map { $0 * invNorm }
        } else {
            depthSignature = rawSig
        }

        // 5. Fit plane specifically to outer perimeter ring (0.40 <= rSq <= 0.95: cheeks, forehead, chin)
        // and measure nose protrusion above that facial base plane.
        let ringPoints = faceSamples.filter { $0.radiusSq >= 0.40 }
        let basePlane = fitPlane(ringPoints.map { ($0.nx, $0.ny, $0.d) }) ?? fullPlane

        // Determine nose pixel position (Vision nose landmark if available, else face center)
        let noseU: Double
        let noseV: Double
        if let nose = noseNormalizedCenter {
            noseU = min(max((Double(nose.x) - Double(innerBox.minX)) / Double(innerBox.width), 0.25), 0.75)
            noseV = min(max((Double(innerBox.maxY) - Double(nose.y)) / Double(innerBox.height), 0.25), 0.75)
        } else {
            noseU = 0.5
            noseV = 0.52
        }
        let nosePx = Int(xMin + noseU * boxW)
        let nosePy = Int(yMin + noseV * boxH)
        let noseNx = (noseU - 0.5) * 2.0
        let noseNy = (noseV - 0.5) * 2.0

        // Median of 5x5 patch around nose tip for stability
        var nosePatch: [Float] = []
        nosePatch.reserveCapacity(25)
        for oy in -2...2 {
            for ox in -2...2 {
                let val = readDepth(x: nosePx + ox, y: nosePy + oy)
                if val.isFinite { nosePatch.append(val) }
            }
        }
        guard !nosePatch.isEmpty else { return nil }
        nosePatch.sort()
        let noseDepth = Double(nosePatch[nosePatch.count / 2])
        let basePlaneAtNose = basePlane.a * noseNx + basePlane.b * noseNy + basePlane.c
        // In Depth Anything V2, higher disparity = closer to camera.
        let noseProtrusion = Float((noseDepth - basePlaneAtNose) / normScale)

        // 6. Head-to-Background Depth Cliff: sample pixels just outside the left/right ear silhouette
        // (1.28x...1.58x face width). A real 3D head drops sharply to the room behind; a large flat monitor/tablet
        // spoof stays coplanar across the surrounding surface.
        let faceCenterPxX = (xMin + xMax) * 0.5
        let faceCenterPxY = (yMin + yMax) * 0.5
        let fullFacePxW = Double(normalizedFaceBox.width) * Double(width)
        let fullFacePxH = Double(normalizedFaceBox.height) * Double(height)
        var outerSamples: [Double] = []
        outerSamples.reserveCapacity(32)
        for side in [-1.0, 1.0] {
            for rFactor in [0.68, 0.80] {
                let sx = Int(faceCenterPxX + side * fullFacePxW * rFactor)
                guard sx >= 2, sx < width - 2 else { continue }
                for yOff in [-0.28, -0.10, 0.08, 0.24] {
                    let sy = Int(faceCenterPxY + fullFacePxH * yOff)
                    guard sy >= 2, sy < height - 2 else { continue }
                    let v = Double(readDepth(x: sx, y: sy))
                    if v.isFinite { outerSamples.append(v) }
                }
            }
        }
        let faceMedianDepth = sortedFaceDepths[sortedFaceDepths.count / 2]
        let backgroundCliff: Float
        if outerSamples.count >= 4 {
            outerSamples.sort()
            let outerMedian = outerSamples[outerSamples.count / 2]
            backgroundCliff = Float((faceMedianDepth - outerMedian) / Double(sceneSpan))
        } else {
            backgroundCliff = 0
        }

        // 7. Calibrated 3D liveness vs flat spoof scoring:
        // Combines nose protrusion, non-planar 3D surface curvature, and head-to-background depth cliff.
        let protrusionLive = clamp((noseProtrusion - 0.015) / 0.075, 0, 1)
        let curvatureLive = clamp((planarityResidual - 0.018) / 0.065, 0, 1)
        let cliffLive = clamp((backgroundCliff - 0.08) / 0.28, 0, 1)
        let depth3DScore = 0.50 * protrusionLive + 0.35 * curvatureLive + 0.15 * cliffLive

        // Flat spoof score is high ONLY when BOTH nose protrusion is near-zero/negative AND the surface is ultra-flat;
        // if the face also sits coplanar with its surroundings (no background cliff), flat-screen confidence increases.
        let flatProtrusion = clamp((0.012 - noseProtrusion) / 0.014, 0, 1)
        let flatCurvature = clamp((0.020 - planarityResidual) / 0.016, 0, 1)
        let flatCliffBoost: Float = (outerSamples.count >= 4 && backgroundCliff < 0.05) ? 1.15 : 1.0
        let flatSpoofScore = clamp(flatProtrusion * flatCurvature * flatCliffBoost, 0, 1)

        return NeuralDepthReading(
            noseProtrusion: noseProtrusion,
            planarityResidual: planarityResidual,
            backgroundCliff: backgroundCliff,
            depth3DScore: depth3DScore,
            flatSpoofScore: flatSpoofScore,
            depthSignature: depthSignature,
            inferenceMs: inferenceMs
        )
    }

    /// Cosine similarity between two L2-normalized 9-zone 3D facial depth signatures (-1...1).
    static func signatureSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i] }
        return dot
    }

    /// Averages multiple enrolled 3D depth signatures into a single L2-normalized centroid profile.
    static func meanSignature(of signatures: [[Float]]) -> [Float]? {
        let valid = signatures.filter { $0.count == 9 }
        guard !valid.isEmpty else { return nil }
        var sum = [Float](repeating: 0, count: 9)
        for sig in valid {
            for i in 0..<9 { sum[i] += sig[i] }
        }
        var normSq: Float = 0
        for v in sum { normSq += v * v }
        guard normSq > 1e-8 else { return nil }
        let inv = 1.0 / normSq.squareRoot()
        return sum.map { $0 * inv }
    }

    /// Solves 3x3 normal equations for least-squares plane z = a*x + b*y + c via Cramer's rule.
    private static func fitPlane(_ pts: [(Double, Double, Double)]) -> (a: Double, b: Double, c: Double)? {
        let n = Double(pts.count)
        guard n >= 3 else { return nil }
        var sx = 0.0, sy = 0.0, sz = 0.0
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        var sxz = 0.0, syz = 0.0

        for (x, y, z) in pts {
            sx += x; sy += y; sz += z
            sxx += x * x; sxy += x * y; syy += y * y
            sxz += x * z; syz += y * z
        }

        // Matrix M:
        // [ sxx  sxy  sx ] [a]   [sxz]
        // [ sxy  syy  sy ] [b] = [syz]
        // [ sx   sy   n  ] [c]   [sz ]
        let det = sxx * (syy * n - sy * sy)
                - sxy * (sxy * n - sy * sx)
                + sx  * (sxy * sy - syy * sx)
        guard abs(det) > 1e-12 else { return nil }

        let detA = sxz * (syy * n - sy * sy)
                 - sxy * (syz * n - sy * sz)
                 + sx  * (syz * sy - syy * sz)
        let detB = sxx * (syz * n - sy * sz)
                 - sxz * (sxy * n - sy * sx)
                 + sx  * (sxy * sz - syz * sx)
        let detC = sxx * (syy * sz - syz * sy)
                 - sxy * (sxy * sz - syz * sx)
                 + sxz * (sxy * sy - syy * sx)

        return (detA / det, detB / det, detC / det)
    }

    /// Universal IEEE-754 half-precision reader (uses native `Float16` on Apple Silicon and pure bit conversion on Intel x86_64).
    private static func readHalfFloat(_ rowPtr: UnsafeMutableRawPointer, index: Int) -> Float {
        #if arch(arm64)
        return Float(rowPtr.assumingMemoryBound(to: Float16.self)[index])
        #else
        let bits = rowPtr.assumingMemoryBound(to: UInt16.self)[index]
        let sign = UInt32(bits & 0x8000) << 16
        let exp = Int((bits >> 10) & 0x1F)
        let frac = UInt32(bits & 0x03FF)
        if exp == 0 {
            if frac == 0 { return Float(bitPattern: sign) }
            var f = frac
            var e = -14
            while (f & 0x0400) == 0 { f <<= 1; e -= 1 }
            f &= 0x03FF
            return Float(bitPattern: sign | UInt32(e + 127) << 23 | (f << 13))
        } else if exp == 31 {
            return Float(bitPattern: sign | 0x7F800000 | (frac << 13))
        }
        return Float(bitPattern: sign | UInt32(exp - 15 + 127) << 23 | (frac << 13))
        #endif
    }

    private static func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        min(max(v, lo), hi)
    }
}
