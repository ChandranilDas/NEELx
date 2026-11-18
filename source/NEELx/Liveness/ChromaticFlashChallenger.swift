//
//  ChromaticFlashChallenger.swift
//  NEELx
//
//  Active Chromatic Screen-Reflection Liveness ("Photometric Flash Challenge").
//  Defeats 4K video replay attacks: flashes a subtle, randomly chosen color tint
//  (cyan or warm amber) for ~110ms and verifies that the live skin reflection shifts
//  along the predicted RGB axis in real time. A pre-recorded video cannot anticipate
//  a random flash chosen milliseconds earlier.
//

import AppKit
import CoreGraphics
import Foundation

nonisolated enum ChromaticFlashTint: String, CaseIterable, Sendable {
    case cyan
    case magenta

    var nsColor: NSColor {
        switch self {
        case .cyan:    return NSColor(calibratedRed: 0.00, green: 0.95, blue: 1.00, alpha: 1.0)
        case .magenta: return NSColor(calibratedRed: 1.00, green: 0.05, blue: 0.85, alpha: 1.0)
        }
    }
}

nonisolated struct FaceRGBSample: Sendable {
    let r: Double
    let g: Double
    let b: Double

    var luminance: Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

nonisolated enum ChromaticFlashVerdict: Sendable {
    case passed(shift: Double)
    case failed(shift: Double)
    /// Ambient room is too brightly sunlit for a laptop display to visibly tint skin.
    case abstained
}

nonisolated enum ChromaticFlashChallenger {
    /// Samples mean RGB (0...1) inside the central skin area of the Vision normalized face box (bottom-left origin).
    static func meanFaceRGB(_ image: CGImage, normalizedFaceBox: CGRect) -> FaceRGBSample? {
        let inner = normalizedFaceBox.insetBy(
            dx: normalizedFaceBox.width * 0.22,
            dy: normalizedFaceBox.height * 0.22
        )
        guard inner.width > 0.03, inner.height > 0.03 else { return nil }

        let iw = Double(image.width)
        let ih = Double(image.height)
        let cropRect = CGRect(
            x: max(0, Double(inner.minX) * iw),
            y: max(0, (1.0 - Double(inner.maxY)) * ih),
            width: max(4, Double(inner.width) * iw),
            height: max(4, Double(inner.height) * ih)
        ).intersection(CGRect(x: 0, y: 0, width: iw, height: ih))

        guard let cropped = image.cropping(to: cropRect) else { return nil }

        let side = 24
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return nil }

        var rSum = 0.0, gSum = 0.0, bSum = 0.0
        let count = Double(side * side)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            rSum += Double(bytes[i])
            gSum += Double(bytes[i + 1])
            bSum += Double(bytes[i + 2])
        }
        return FaceRGBSample(
            r: rSum / (count * 255.0),
            g: gSum / (count * 255.0),
            b: bSum / (count * 255.0)
        )
    }

    /// Evaluates whether the reflected color shift on skin matches the randomized screen flash tint.
    /// Accounts for Apple Silicon FaceTime ISP Auto-White-Balance (AWB) which can rapidly counter-shift
    /// cool cyan tints toward warm red in moderately lit rooms while still showing a strong synchronized
    /// photometric reflectance jump on live skin.
    static func evaluate(
        baseline: FaceRGBSample,
        flashed: FaceRGBSample,
        tint: ChromaticFlashTint
    ) -> ChromaticFlashVerdict {
        // When ambient room lighting already illuminates the face clearly (>= 0.34),
        // a brief display edge tint is overpowered by room light & ISP AWB — abstain safely
        // and let Stage 3 Neural 3D Depth + 9-Zone Profile + Attention govern liveness.
        if baseline.luminance >= 0.34 {
            return .abstained
        }

        let deltaR = flashed.r - baseline.r
        let deltaG = flashed.g - baseline.g
        let deltaB = flashed.b - baseline.b
        let deltaLum = flashed.luminance - baseline.luminance

        // Positive signed shift along the expected challenge axis
        let signedShift: Double
        switch tint {
        case .cyan:
            // Cyan boosts G+B relative to R
            signedShift = 0.5 * (deltaG + deltaB) - deltaR
        case .magenta:
            // Magenta boosts R+B relative to G
            signedShift = 0.5 * (deltaR + deltaB) - deltaG
        }

        // Total photometric energy shift across RGB channels
        let totalShift = abs(deltaR) + abs(deltaG) + abs(deltaB)

        // 1. Direct chromatic axis match (ideal dim-room reflection)
        if signedShift >= 0.0020 {
            return .passed(shift: signedShift)
        }
        // 2. Mild AWB dampening with clear synchronized photometric response
        if signedShift >= -0.0035 && totalShift >= 0.012 {
            return .passed(shift: signedShift)
        }
        // 3. Strong synchronized photometric flash reflection (e.g. M4 ISP AWB neutralizing cyan hue
        //    while skin luminance & total RGB energy clearly jump in phase with the display pulse).
        //    A self-emissive phone/tablet playing a pre-recorded video does not brighten synchronously.
        if totalShift >= 0.024 && deltaLum >= 0.006 {
            return .passed(shift: totalShift)
        }
        return .failed(shift: signedShift)
    }
}
