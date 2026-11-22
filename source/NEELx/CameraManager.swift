//
//  CameraManager.swift
//  NEELx
//
//  Owns the AVCaptureSession and publishes the newest camera frame as a CGImage. Runs entirely on-device.
//

@preconcurrency import AVFoundation
import CoreImage
import Observation

enum CameraPermission {
    case notDetermined
    case granted
    case denied
}

/// `source` is a `CIImage` — a lazy recipe, not rendered pixels — so holding onto it costs nothing until `renderCrop` uses it.
struct CameraFrame {
    let id: UInt64
    let image: CGImage
    let source: CIImage
    let sourceSize: CGSize
}

@Observable
@MainActor
final class CameraManager: NSObject {
    private(set) var permission: CameraPermission = .notDetermined
    private(set) var isRunning: Bool = false
    private(set) var currentFrame: CameraFrame?
    private(set) var errorMessage: String?

    /// Active camera device name (or currently resolved default)
    var currentDeviceName: String {
        currentInput?.device.localizedName ?? CameraDeviceCatalog.resolvedDevice()?.localizedName ?? "FaceTime HD Camera"
    }

    /// Exposed read-only so `CameraPreviewView` can attach a preview layer to the same session.
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "local.neelx.camera.session")

    /// Dual-path companion capture session for Mac's built-in webcam when phone/tablet is primary
    private let companionSession = AVCaptureSession()
    private let companionVideoOutput = AVCaptureVideoDataOutput()
    private var companionInput: AVCaptureDeviceInput?
    private let companionPublisher = FramePublisher()
    private var isCompanionConfigured = false
    private(set) var isDualPathActive = false

    /// Handed to the delegate outside the actor; only ever touched via `Task { @MainActor ... }`.
    private let framePublisher = FramePublisher()

    /// Watchdog task for Continuity Camera latency fallback
    private var continuityWatchdogTask: Task<Void, Never>?
    private var receivedFirstFrame = false

    override init() {
        super.init()
        framePublisher.owner = self
        companionPublisher.owner = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruption(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: nil
        )
    }

    @objc private func handleSessionInterruption(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.currentInput?.device.deviceType == .continuityCamera {
                self.fallbackToBuiltInCamera(reason: "Continuity Camera interrupted by device")
            }
        }
    }

    func start() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permission = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permission = granted ? .granted : .denied
        default:
            permission = .denied
        }

        guard permission == .granted else {
            errorMessage = "Camera access not granted (status: \(describe(status))). " +
                (status == .restricted
                    ? "macOS reports this as *restricted* — not a simple user denial. This usually means Screen Time content restrictions or an MDM/profile policy is blocking camera access for this app; toggling it in System Settings > Privacy & Security > Camera won't help until that restriction is lifted."
                    : "Enable it in System Settings > Privacy & Security > Camera. If NEELx isn't listed there, quit the app, run `tccutil reset Camera local.neelx` in Terminal, then relaunch so macOS asks again.")
            return
        }

        errorMessage = nil
        receivedFirstFrame = false
        configureSessionIfNeeded()
        reconcileDeviceIfNeeded()
        reconcileCompanionSessionIfNeeded()

        let dualActive = isDualPathActive
        sessionQueue.async { [session, companionSession] in
            if !session.isRunning {
                session.startRunning()
            }
            if dualActive && !companionSession.isRunning {
                companionSession.startRunning()
            }
        }
        isRunning = true

        // Fast watchdog for Continuity Camera: if no frame arrives within 850ms,
        // seamlessly fall back to the built-in webcam so user is never locked out
        if currentInput?.device.deviceType == .continuityCamera {
            continuityWatchdogTask?.cancel()
            continuityWatchdogTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(850))
                guard let self, self.isRunning, !self.receivedFirstFrame else { return }
                if self.currentInput?.device.deviceType == .continuityCamera {
                    self.fallbackToBuiltInCamera(reason: "Continuity Camera delayed (>850ms)")
                }
            }
        }
    }

    func stop() {
        continuityWatchdogTask?.cancel()
        continuityWatchdogTask = nil
        sessionQueue.async { [session, companionSession] in
            if session.isRunning {
                session.stopRunning()
            }
            if companionSession.isRunning {
                companionSession.stopRunning()
            }
        }
        isRunning = false
        currentFrame = nil
    }

    private func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    private var isConfigured = false
    private var currentInput: AVCaptureDeviceInput?

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        // `.high` doesn't guarantee the sensor's max resolution; macOS (unlike iOS) doesn't fight an explicitly-set
        // `activeFormat`, so leaving this at `.high` and locking the format separately below is sufficient.
        session.sessionPreset = .high

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(framePublisher, queue: sessionQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
    }

    /// Called on every `start()` so a camera preference change in Settings takes effect without an app restart.
    private func reconcileDeviceIfNeeded() {
        guard let device = CameraDeviceCatalog.resolvedDevice() else {
            errorMessage = "No camera device found."
            return
        }
        guard device.uniqueID != currentInput?.device.uniqueID else { return }

        session.beginConfiguration()
        if let currentInput {
            session.removeInput(currentInput)
        }
        if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
            selectHighestResolutionFormat(for: device)
        } else {
            currentInput = nil
            errorMessage = "No camera device found."
        }
        session.commitConfiguration()
    }

    /// Highest resolution regardless of fps — Vision still works from the downscaled frame; this only affects
    /// what `CameraFrame.source` (and therefore `renderCrop`) has to work with.
    private func selectHighestResolutionFormat(for device: AVCaptureDevice) {
        let best = device.formats.max { lhs, rhs in
            let l = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let r = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(l.width) * Int(l.height) < Int(r.width) * Int(r.height)
        }
        guard let best else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.unlockForConfiguration()
        } catch {
            errorMessage = "Couldn't select the camera's highest-resolution format: \(error.localizedDescription)"
        }
    }

    fileprivate func publish(frame: CameraFrame) {
        receivedFirstFrame = true
        continuityWatchdogTask?.cancel()
        continuityWatchdogTask = nil
        currentFrame = frame
    }

    /// Sets up the secondary companion capture session on the built-in webcam when dual-path unlock is enabled.
    private func reconcileCompanionSessionIfNeeded() {
        guard NEELxSettings.shared.dualCameraConcurrentUnlock,
              let current = currentInput?.device,
              current.deviceType == .continuityCamera || current.deviceType == .external
        else {
            isDualPathActive = false
            return
        }

        guard let builtIn = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            isDualPathActive = false
            return
        }

        if !isCompanionConfigured {
            isCompanionConfigured = true
            companionSession.beginConfiguration()
            companionSession.sessionPreset = .high
            companionVideoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            companionVideoOutput.alwaysDiscardsLateVideoFrames = true
            companionVideoOutput.setSampleBufferDelegate(companionPublisher, queue: sessionQueue)
            if companionSession.canAddOutput(companionVideoOutput) {
                companionSession.addOutput(companionVideoOutput)
            }
            companionSession.commitConfiguration()
        }

        if companionInput?.device.uniqueID != builtIn.uniqueID {
            companionSession.beginConfiguration()
            if let companionInput {
                companionSession.removeInput(companionInput)
            }
            if let input = try? AVCaptureDeviceInput(device: builtIn), companionSession.canAddInput(input) {
                companionSession.addInput(input)
                companionInput = input
                selectHighestResolutionFormat(for: builtIn)
                isDualPathActive = true
            } else {
                companionInput = nil
                isDualPathActive = false
            }
            companionSession.commitConfiguration()
        } else {
            isDualPathActive = true
        }
    }

    /// Seamless fallback to built-in webcam if Continuity Camera stalls or is interrupted
    private func fallbackToBuiltInCamera(reason: String) {
        guard let builtIn = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ?? AVCaptureDevice.default(for: .video) else { return }
        guard builtIn.uniqueID != currentInput?.device.uniqueID else { return }

        session.beginConfiguration()
        if let currentInput {
            session.removeInput(currentInput)
        }
        if let input = try? AVCaptureDeviceInput(device: builtIn), session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
            selectHighestResolutionFormat(for: builtIn)
        }
        session.commitConfiguration()
    }

    /// Renders a native-resolution crop of `imageRect` from `frame.source`, for spoof-cue extraction which
    /// needs pixel detail (screen texture, moiré, gloss) the downscaled working frame throws away.
    nonisolated static func renderCrop(from frame: CameraFrame, imageRect: CGRect, maxEdge: CGFloat = 448) -> CGImage? {
        let workingWidth = CGFloat(frame.image.width)
        let workingHeight = CGFloat(frame.image.height)
        guard workingWidth > 0, workingHeight > 0 else { return nil }
        let scaleX = frame.sourceSize.width / workingWidth
        let scaleY = frame.sourceSize.height / workingHeight

        // Expand ~1.3x so device edges/bezels are captured for texture/moiré cues.
        let expanded = imageRect.insetBy(dx: -imageRect.width * 0.15, dy: -imageRect.height * 0.15)

        // Flip from `imageRect`'s top-left/y-down space to Core Image's bottom-left/y-up (reverse of FaceDetector.convertToImageSpace).
        let nativeX = expanded.origin.x * scaleX
        let nativeWidth = expanded.width * scaleX
        let nativeHeight = expanded.height * scaleY
        let nativeY = frame.sourceSize.height - (expanded.origin.y + expanded.height) * scaleY
        var nativeRect = CGRect(x: nativeX, y: nativeY, width: nativeWidth, height: nativeHeight)

        let sourceExtent = CGRect(origin: .zero, size: frame.sourceSize)
        nativeRect = nativeRect.intersection(sourceExtent)
        guard !nativeRect.isEmpty else { return nil }

        var cropped = frame.source.cropped(to: nativeRect)
            .transformed(by: CGAffineTransform(translationX: -nativeRect.minX, y: -nativeRect.minY))
        let longEdge = max(nativeRect.width, nativeRect.height)
        if longEdge > maxEdge {
            let scale = maxEdge / longEdge
            cropped = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        return cropRenderContext.createCGImage(cropped, from: cropped.extent)
    }

    /// `CIContext` is expensive to create and safe to reuse concurrently. Explicitly `nonisolated` since a `static let`
    /// on this `@MainActor` class would otherwise be main-actor-isolated, which the `nonisolated renderCrop` can't touch.
    private nonisolated static let cropRenderContext = CIContext()

    /// Sample-buffer callbacks arrive on `sessionQueue`, off the main actor; this delegate converts there, then hops back.
    private final class FramePublisher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        weak var owner: CameraManager?
        private let ciContext = CIContext()
        /// Detection only needs a modest resolution; the live preview renders from the capture session directly and
        /// is unaffected. The undownscaled `source` is kept alongside for callers needing native pixels (`renderCrop`).
        private let maxLongEdge: CGFloat = 640
        private var nextFrameID: UInt64 = 0

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
            let sourceExtent = sourceImage.extent
            var ciImage = sourceImage
            let longEdge = max(ciImage.extent.width, ciImage.extent.height)
            if longEdge > maxLongEdge {
                let scale = maxLongEdge / longEdge
                ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

            nextFrameID &+= 1
            let frame = CameraFrame(
                id: nextFrameID,
                image: cgImage,
                source: sourceImage,
                sourceSize: sourceExtent.size
            )

            Task { @MainActor [weak owner] in
                owner?.publish(frame: frame)
            }
        }
    }
}
