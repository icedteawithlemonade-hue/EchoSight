import SwiftUI
import AVFoundation
import Combine

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var isAuthorized = false
    @Published var cameraError: String?
    private var isConfigured = false
    private let outputQueue = DispatchQueue(label: "echosight.camera.output")
    private let sessionQueue = DispatchQueue(label: "echosight.camera.session")
    private let sampleDeliveryInterval: CFTimeInterval = 1.0 / 12.0
    private var lastSampleDeliveryTime: CFTimeInterval = 0
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
            isAuthorized = true
        case .notDetermined:
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
            isAuthorized = false
            cameraError = "Camera access is required. Enable it in Settings."
        }
    }

    var hasCameraInput: Bool {
        !session.inputs.isEmpty
    }

    private func setupSession() {
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }

        guard let device = preferredBackCamera() else {
            cameraError = "Camera preview is not available in the simulator. Run on a physical device to use camera features."
            session.commitConfiguration()
            return
        }
        configureDeviceForRecognition(device)
        do {
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
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .standard
            }
        }

        session.commitConfiguration()
        cameraError = nil
    }

    private func preferredBackCamera() -> AVCaptureDevice? {
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
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }

            let frameDuration = CMTime(value: 1, timescale: 30)
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
        guard isAuthorized, !session.isRunning else { return }
        guard !session.inputs.isEmpty else {
            cameraError = "Camera preview is not available in the simulator. Run on a physical device to use camera features."
            return
        }
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastSampleDeliveryTime >= sampleDeliveryInterval else { return }
        lastSampleDeliveryTime = now
        onSampleBuffer?(sampleBuffer)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Nothing to update dynamically for the preview layer here.
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        return layer as! AVCaptureVideoPreviewLayer
    }
}
