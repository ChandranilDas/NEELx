//
//  DeviceBezelDetector.swift
//  NEELx
//
//  Looks for a device bezel (phone/tablet) around the face via
//  VNDetectRectanglesRequest; only ever produces positive evidence of
//  spoofing, never positive evidence of liveness.
//

import Vision
import CoreGraphics

struct DeviceBezelObservation {
    /// Largest device-plausible rectangle found this frame, same pixel space as `DetectedFace.boundingBox`.
    let rectangle: CGRect?
    /// Fraction of the face's bounding box area that falls inside `rectangle`.
    let faceOverlapFraction: CGFloat?

    nonisolated static let none = DeviceBezelObservation(rectangle: nil, faceOverlapFraction: nil)
}

nonisolated enum DeviceBezelDetector {
    /// First-pass estimates, not validated against real footage — tune here if false positives/negatives show up.
    private static func makeRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.6
        // Fraction of image area, not width/height.
        request.minimumSize = 0.15
        request.maximumObservations = 3
        // Covers phone-in-portrait (0.35) through near-square tablet crop (1.0).
        request.minimumAspectRatio = 0.35
        request.maximumAspectRatio = 1.0
        // Generous so a phone held at a slight angle still registers.
        request.quadratureTolerance = 30

        return request
    }

    /// Synchronous and CPU-bound — call from a background task, same as `FaceDetector.detectFaces`.
    static func detect(in image: CGImage, faceBoundingBox: CGRect) -> DeviceBezelObservation {
        let request = makeRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results, !results.isEmpty
        else { return .none }

        let imageSize = CGSize(width: image.width, height: image.height)
        let imageArea = max(1, imageSize.width * imageSize.height)
        let faceArea = faceBoundingBox.width * faceBoundingBox.height
        let candidates = results
            .map { FaceDetector.convertToImageSpace($0.boundingBox, imageSize: imageSize) }
            .filter { rect in
                let rectArea = rect.width * rect.height
                // Exclude room-scale architectural rectangles (door frames, walls, windows)
                // where the rectangle covers most of the camera frame and dwarfs the face.
                if rectArea / imageArea > 0.68 && (faceArea / max(1, rectArea)) < 0.08 {
                    return false
                }
                return true
            }
        // Largest plausible device candidate overlapping the face
        guard let largest = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return .none
        }

        guard faceArea > 0 else { return DeviceBezelObservation(rectangle: largest, faceOverlapFraction: nil) }
        let intersection = largest.intersection(faceBoundingBox)
        let overlap = (intersection.width * intersection.height) / faceArea
        return DeviceBezelObservation(rectangle: largest, faceOverlapFraction: overlap)
    }
}
