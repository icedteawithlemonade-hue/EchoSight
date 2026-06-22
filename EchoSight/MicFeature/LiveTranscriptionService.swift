import AVFoundation
import Combine
import Foundation
import Speech

// Wraps Apple's Speech framework for live captions.
// AudioCaptureService provides microphone buffers; this service streams them to
// SFSpeechRecognizer and publishes transcript text for SwiftUI.
final class LiveTranscriptionService: ObservableObject {
    // Full transcript published for the UI.
    @Published var transcript: String = ""
    // Whether Speech framework is actively recognizing.
    @Published var isListening: Bool = false
    // User-readable failure reason.
    @Published var error: String?

    // Default recognizer uses the current locale.
    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    // Request receives raw audio buffers from AudioCaptureService.
    private var request: SFSpeechAudioBufferRecognitionRequest?
    // Task owns the active recognition session.
    private var task: SFSpeechRecognitionTask?
    // Buffers are appended off main so UI stays responsive.
    private let processingQueue = DispatchQueue(label: "echosight.speech.stream")

    func requestPermission() async -> Bool {
        // Speech recognition has its own permission separate from microphone access.
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    // Return a simple true/false to MicViewModel.
                    switch status {
                    case .authorized:
                        continuation.resume(returning: true)
                    case .denied, .restricted, .notDetermined:
                        continuation.resume(returning: false)
                    @unknown default:
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    func start() -> Bool {
        // If recognizer cannot be created for this locale, captions cannot start.
        guard let recognizer else {
            error = "Speech recognition is unavailable for this language."
            isListening = false
            return false
        }
        guard recognizer.isAvailable else {
            // Speech service can be temporarily unavailable.
            error = "Speech recognition is unavailable on this device."
            isListening = false
            return false
        }

        // New session starts with a clean transcript.
        transcript = ""
        error = nil
        // Cancel any old task before creating a new request.
        task?.cancel()
        task = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        // Partial results make captions appear live instead of only at the end.
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            // Privacy choice: require local speech recognition.
            request.requiresOnDeviceRecognition = true
        } else {
            // Do not fall back to server speech recognition.
            error = "On-device speech recognition isn't available. Captions are disabled."
            isListening = false
            return false
        }
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    // bestTranscription is Apple's highest-confidence live caption text.
                    self.transcript = result.bestTranscription.formattedString
                    self.isListening = true
                }
            }
            if let error {
                DispatchQueue.main.async {
                    // Publish recognition errors for the banner.
                    self.error = error.localizedDescription
                    self.isListening = false
                }
            }
        }
        isListening = true
        return true
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // AudioCaptureService calls this for every captured mic buffer.
        processingQueue.async { [weak self] in
            self?.request?.append(buffer)
        }
    }

    func stop() {
        // End request and cancel recognition task to release Speech resources.
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        DispatchQueue.main.async {
            self.isListening = false
        }
    }
}
