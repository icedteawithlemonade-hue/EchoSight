import SwiftUI
import AVFoundation
import Combine

// CameraManager owns the AVCaptureSession used by all camera tools.
// It requests permission, configures the back camera, exposes preview frames,
// and throttles frame delivery so Vision/Core ML does not overload the UI.
final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // The shared capture session powers both the preview layer and video frames.
    let session = AVCaptureSession()
    // Permission status observed by SwiftUI pages.
    @Published var isAuthorized = false
    // Human-readable error shown inside CameraPreviewCard.
    @Published var cameraError: String?
    // Ensures configure() only builds the session once per CameraManager.
    private var isConfigured = false
    // Output queue receives camera frames.
    private let outputQueue = DispatchQueue(label: "echosight.camera.output")
    // Session queue starts/stops AVCaptureSession away from the main thread.
    private let sessionQueue = DispatchQueue(label: "echosight.camera.session")
    // Deliver at most 12 frames per second to Vision/Core ML.
    private let sampleDeliveryInterval: CFTimeInterval = 1.0 / 12.0
    private var lastSampleDeliveryTime: CFTimeInterval = 0
    // Feature pages set this closure to receive sampled frames.
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    func configure() {
        // Safe to call from onAppear repeatedly.
        guard !isConfigured else { return }
        isConfigured = true

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Permission already granted, so build session now.
            setupSession()
            isAuthorized = true
        case .notDetermined:
            // First run asks the user for camera permission.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.setupSession()
                    }
                    self.isAuthorized = granted
                }
            }
        default:
            // Denied/restricted states need Settings action from the user.
            isAuthorized = false
            cameraError = "Camera access is required. Enable it in Settings."
        }
    }

    var hasCameraInput: Bool {
        // Used by the preview card to distinguish simulator/missing-camera cases.
        !session.inputs.isEmpty
    }

    private func setupSession() {
        // Batch session changes between begin/commit for AVCapture correctness.
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) {
            // 720p is sharp enough for recognition without huge frames.
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }

        guard let device = preferredBackCamera() else {
            // Simulator has no real back camera, so show a useful message.
            cameraError = "Camera preview is not available in the simulator. Run on a physical device to use camera features."
            session.commitConfiguration()
            return
        }
        configureDeviceForRecognition(device)
        do {
            // AVCaptureDeviceInput connects the physical camera to the session.
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                cameraError = "Unable to add the camera input."
            }
        } catch {
            cameraError = "Unable to configure the camera."
            session.commitConfiguration()
            return
        }

        let videoOutput = AVCaptureVideoDataOutput()
        // Drop late frames instead of queueing them and causing lag.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            // BGRA pixel format is easy for Vision and manual luma reading.
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                // App UI is portrait, so deliver portrait-oriented buffers.
                connection.videoOrientation = .portrait
            }
            if connection.isVideoStabilizationSupported {
                // Stabilization helps recognition by reducing frame shake.
                connection.preferredVideoStabilizationMode = .standard
            }
        }

        session.commitConfiguration()
        cameraError = nil
    }

    private func preferredBackCamera() -> AVCaptureDevice? {
        // Prefer multi-camera hardware when available, fall back to wide angle.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private func configureDeviceForRecognition(_ device: AVCaptureDevice) {
        do {
            // Camera hardware settings require lock/unlock.
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusModeSupported(.continuousAutoFocus) {
                // Continuous focus helps object/OCR/currency detection stay sharp.
                device.focusMode = .continuousAutoFocus
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                // Auto exposure handles changing light conditions.
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.isLowLightBoostSupported {
                // Helps in dark rooms if the device supports it.
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }

            let frameDuration = CMTime(value: 1, timescale: 30)
            // Locking to 30 FPS reduces camera workload versus higher frame rates.
            let supportsThirtyFPS = device.activeFormat.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= 30 && range.maxFrameRate >= 30
            }
            if supportsThirtyFPS {
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
            }
        } catch {
            cameraError = "Camera focus and exposure tuning was unavailable."
        }
    }

    func start() {
        // Do not start if permission is missing or session is already running.
        guard isAuthorized, !session.isRunning else { return }
        guard !session.inputs.isEmpty else {
            cameraError = "Camera preview is not available in the simulator. Run on a physical device to use camera features."
            return
        }
        sessionQueue.async {
            // AVCaptureSession startRunning can block, so it stays off main.
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        // Stop capture when leaving a camera page to save battery.
        guard session.isRunning else { return }
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Throttle frame delivery before handing it to expensive Vision pipelines.
        let now = CACurrentMediaTime()
        guard now - lastSampleDeliveryTime >= sampleDeliveryInterval else { return }
        lastSampleDeliveryTime = now
        onSampleBuffer?(sampleBuffer)
    }
}

// Bridges Apple's AVCaptureVideoPreviewLayer into SwiftUI.
struct CameraPreview: UIViewRepresentable {
    // SwiftUI wrapper around UIKit preview layer.
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        // Attach the session once when the UIView is created.
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Nothing to update dynamically for the preview layer here.
    }
}

// A UIView whose backing layer is AVCaptureVideoPreviewLayer.
final class PreviewView: UIView {
    // Override backing layer so this view is literally an AVCaptureVideoPreviewLayer.
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        return layer as! AVCaptureVideoPreviewLayer
    }
}
