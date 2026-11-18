import CoreML
import CoreGraphics
import CoreVideo
import Foundation

// Quick standalone benchmark for DepthAnythingV2SmallF16.mlmodelc on Apple Silicon ANE.
let modelPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "source/NEELx/Resources/DepthAnythingV2SmallF16.mlmodelc"
let modelURL = URL(fileURLWithPath: modelPath)

let config = MLModelConfiguration()
config.computeUnits = .all

let t0 = CFAbsoluteTimeGetCurrent()
let model = try MLModel(contentsOf: modelURL, configuration: config)
let loadMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
print(String(format: "Loaded DepthAnythingV2SmallF16 in %.1f ms", loadMs))

let width = 518
let height = 392
var pb: CVPixelBuffer?
let attrs: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
]
CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
guard let inputBuffer = pb else { fatalError("Failed to create pixel buffer") }

// Fill with a smooth synthetic gradient (flat plane test)
CVPixelBufferLockBaseAddress(inputBuffer, [])
if let base = CVPixelBufferGetBaseAddress(inputBuffer) {
    let bpr = CVPixelBufferGetBytesPerRow(inputBuffer)
    for y in 0..<height {
        let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
        for x in 0..<width {
            row[x * 4 + 0] = UInt8((x * 255) / width)
            row[x * 4 + 1] = UInt8((y * 255) / height)
            row[x * 4 + 2] = 128
            row[x * 4 + 3] = 255
        }
    }
}
CVPixelBufferUnlockBaseAddress(inputBuffer, [])

let provider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: inputBuffer)])

// Warmup run + 5 timed runs
_ = try model.prediction(from: provider)
var times: [Double] = []
var lastDepth: CVPixelBuffer?
for _ in 0..<5 {
    let s = CFAbsoluteTimeGetCurrent()
    let out = try model.prediction(from: provider)
    let ms = (CFAbsoluteTimeGetCurrent() - s) * 1000.0
    times.append(ms)
    lastDepth = out.featureValue(for: "depth")?.imageBufferValue
}

let avgMs = times.reduce(0, +) / Double(times.count)
let minMs = times.min() ?? 0
print(String(format: "ANE inference latency (5 runs): min = %.1f ms, avg = %.1f ms", minMs, avgMs))

if let depth = lastDepth {
    let fmt = CVPixelBufferGetPixelFormatType(depth)
    let dw = CVPixelBufferGetWidth(depth)
    let dh = CVPixelBufferGetHeight(depth)
    print("Output depth buffer: \(dw)x\(dh), pixelFormat=\(fmt) (OneComponent16Half=\(kCVPixelFormatType_OneComponent16Half))")
}
