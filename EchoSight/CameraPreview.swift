import SwiftUI
import AVFoundation
import Combine

enum CameraLens: String, CaseIterable, Identifiable {
    case wide
    case telephoto

    var id: String { rawValue }
    var title: String {
        switch self {
        case .wide: return "Wide"
        case .telephoto: return "Telephoto"
        }
    }
}

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var isAuthorized = false
    @Published var currentLens: CameraLens = .wide
    @Published var maxZoomFactor: CGFloat = 8.0
    private var isConfigured = false
    private let outputQueue = DispatchQueue(label: "echosight.camera.output")
    private let sessionQueue = DispatchQueue(label: "echosight.camera.session")
    private let deviceQueue = DispatchQueue(label: "echosight.camera.device")
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isReconfiguring = false
    private var desiredLens: CameraLens = .wide
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    func configure(lens: CameraLens = .wide) {
        desiredLens = lens
        guard !isConfigured else {
            switchLens(to: lens)
            return
        }
        isConfigured = true

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            sessionQueue.async { [weak self] in
                self?.setupSession(lens: lens)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isAuthorized = granted
                    if granted {
                        self.sessionQueue.async {
                            self.setupSession(lens: lens)
                        }
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }

    private func setupSession(lens: CameraLens) {
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let currentInput = videoDeviceInput {
            session.removeInput(currentInput)
        }

        guard let device = cameraDevice(for: lens) else {
            session.commitConfiguration()
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                videoDeviceInput = input
                DispatchQueue.main.async {
                    self.currentLens = lens
                }
                updateMaxZoom(from: device)
                configureDeviceForOCR(device)
            }
        } catch {
            session.commitConfiguration()
            return
        }

        if !session.outputs.contains(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        }

        session.commitConfiguration()
    }

    func start() {
        guard isAuthorized, !session.isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onSampleBuffer?(sampleBuffer)
    }

    func switchLens(to lens: CameraLens) {
        guard isAuthorized else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isReconfiguring else { return }
            guard self.currentLens != lens else { return }
            self.isReconfiguring = true
            self.session.beginConfiguration()
            if let currentInput = self.videoDeviceInput {
                self.session.removeInput(currentInput)
            }
            if let device = self.cameraDevice(for: lens) {
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.videoDeviceInput = input
                        DispatchQueue.main.async {
                            self.currentLens = lens
                        }
                        self.updateMaxZoom(from: device)
                        self.configureDeviceForOCR(device)
                    }
                } catch {
                    // keep previous lens if failed
                }
            }
            self.session.commitConfiguration()
            self.isReconfiguring = false
        }
    }

    func setZoom(_ factor: CGFloat, ramp: Bool = true) {
        deviceQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let maxZoom = max(1.0, device.activeFormat.videoMaxZoomFactor)
                let clamped = min(max(1.0, factor), maxZoom)
                if ramp, device.responds(to: #selector(AVCaptureDevice.ramp(toVideoZoomFactor:withRate:))) {
                    if device.isRampingVideoZoom {
                        device.cancelVideoZoomRamp()
                    }
                    device.ramp(toVideoZoomFactor: clamped, withRate: 4.0)
                } else {
                    device.videoZoomFactor = clamped
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.maxZoomFactor = maxZoom
                }
            } catch {
                // no-op; keep existing zoom
            }
        }
    }

    func setFocusLocked(_ locked: Bool) {
        deviceQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if locked {
                    if device.isFocusModeSupported(.locked) {
                        device.focusMode = .locked
                    }
                    if device.isExposureModeSupported(.locked) {
                        device.exposureMode = .locked
                    }
                } else {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
                device.unlockForConfiguration()
            } catch {
                // no-op
            }
        }
    }

    func setTorch(enabled: Bool) {
        deviceQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = enabled ? .on : .off
                device.unlockForConfiguration()
            } catch {
                // no-op
            }
        }
    }

    func applyContinuousFocusAndExposure() {
        deviceQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            self.configureDeviceForOCR(device)
        }
    }

    private func cameraDevice(for lens: CameraLens) -> AVCaptureDevice? {
        let deviceType: AVCaptureDevice.DeviceType = (lens == .telephoto) ? .builtInTelephotoCamera : .builtInWideAngleCamera
        if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private func configureDeviceForOCR(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            // no-op
        }
    }

    private func updateMaxZoom(from device: AVCaptureDevice) {
        DispatchQueue.main.async { [weak self] in
            self?.maxZoomFactor = max(1.0, device.activeFormat.videoMaxZoomFactor)
        }
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
