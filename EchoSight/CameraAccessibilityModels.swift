import AVFoundation
import Combine
import CoreML
import QuartzCore
import SwiftUI
import Vision

final class SpeechAnnouncer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechAnnouncer()

    private let synthesizer = AVSpeechSynthesizer()
    private var lastPhrase: String = ""
    private var lastSpokenAt: Date = .distantPast
    private let debounceInterval: TimeInterval = 1.8
    private var lastSpokenText: String = ""
    var onQueueFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func announce(_ phrase: String) {
        speak(phrase, debounce: true)
    }

    func speak(
        _ text: String,
        rate: Double? = nil,
        pitch: Double? = nil,
        volume: Double? = nil,
        debounce: Bool = false,
        interrupt: Bool = true
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastSpokenText = trimmed
        let now = Date()
        if debounce, trimmed == lastPhrase, now.timeIntervalSince(lastSpokenAt) < debounceInterval {
            return
        }
        lastPhrase = trimmed
        lastSpokenAt = now

        prepareAudioSessionForSpeech()

        let sentences = splitSentences(from: trimmed)
        let voice = preferredVoice()
        let settings = SpeechSettings.load()
        let finalRate = rate ?? settings.rate
        let finalPitch = pitch ?? settings.pitch
        let finalVolume = volume ?? settings.volume

        if interrupt {
            synthesizer.stopSpeaking(at: .immediate)
        }
        for sentence in sentences {
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = voice
            utterance.rate = Float(finalRate)
            utterance.pitchMultiplier = Float(finalPitch)
            utterance.volume = Float(finalVolume)
            utterance.postUtteranceDelay = 0.2
            synthesizer.speak(utterance)
        }
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    func restartIfSpeaking(rate: Double, pitch: Double, volume: Double) {
        guard synthesizer.isSpeaking, !lastSpokenText.isEmpty else { return }
        speak(lastSpokenText, rate: rate, pitch: pitch, volume: volume, debounce: false)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func testVoice() {
        speak("This is a voice test for EchoSight.")
    }

    private func prepareAudioSessionForSpeech() {
        let session = AVAudioSession.sharedInstance()
        let preferredOptions: AVAudioSession.CategoryOptions = [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        let fallbackOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]

        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: preferredOptions)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            do {
                try session.setCategory(.playback, mode: .default, options: fallbackOptions)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                // If the session can't be set, we still allow the synthesizer to try to speak.
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !synthesizer.isSpeaking {
                self.onQueueFinished?()
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !synthesizer.isSpeaking {
                self.onQueueFinished?()
            }
        }
    }

    private func splitSentences(from text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if ".?!\n".contains(char) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }
        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            sentences.append(remaining)
        }
        return sentences
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let settings = SpeechSettings.load()
        if settings.voiceIdentifier != SpeechSettings.autoVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: settings.voiceIdentifier) {
            return voice
        }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let localeIdentifier = Locale.current.identifier
        let languageCode = Locale.current.languageCode ?? "en"

        let candidates = voices.filter { $0.language == localeIdentifier }
        let fallback = voices.filter { $0.language.hasPrefix(languageCode) }
        let pool = candidates.isEmpty ? fallback : candidates
        return bestVoice(from: pool) ?? bestVoice(from: voices)
    }

    private func bestVoice(from voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        guard !voices.isEmpty else { return nil }
        return voices.max { lhs, rhs in
            qualityScore(lhs) < qualityScore(rhs)
        }
    }

    private func qualityScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .enhanced:
            return 2
        case .default:
            return 1
        @unknown default:
            return 1
        }
    }
}

struct SpeechSettings {
    static let voiceIdentifierKey = "speech.voice.identifier"
    static let rateKey = "speech.rate"
    static let pitchKey = "speech.pitch"
    static let volumeKey = "speech.volume"
    static let autoVoiceIdentifier = "auto"

    var voiceIdentifier: String
    var rate: Double
    var pitch: Double
    var volume: Double

    static func load() -> SpeechSettings {
        let defaults = UserDefaults.standard
        let voice = defaults.string(forKey: voiceIdentifierKey) ?? autoVoiceIdentifier
        let rate = defaults.object(forKey: rateKey) as? Double ?? 0.5
        let pitch = defaults.object(forKey: pitchKey) as? Double ?? 1.0
        let volume = defaults.object(forKey: volumeKey) as? Double ?? 0.9
        return SpeechSettings(voiceIdentifier: voice, rate: rate, pitch: pitch, volume: volume)
    }
}

final class AnnouncementController: ObservableObject {
    private let announcer: SpeechAnnouncer
    private let debounceInterval: TimeInterval = 2.6
    private let cooldownInterval: TimeInterval = 1.8
    private var lastSpokenText: String = ""
    private var lastSpokenAt: Date = .distantPast
    private var lastFinishedAt: Date = .distantPast
    private var pendingMessage: String?
    private var pendingPriority: Bool = false
    private var pendingWork: DispatchWorkItem?

    init(announcer: SpeechAnnouncer = SpeechAnnouncer.shared) {
        self.announcer = announcer
        announcer.onQueueFinished = { [weak self] in
            self?.handleFinished()
        }
    }

    func announce(_ text: String, priority: Bool? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let isPriority = priority ?? isHighPriority(trimmed)
        let now = Date()
        if trimmed == lastSpokenText, now.timeIntervalSince(lastSpokenAt) < debounceInterval {
            return
        }
        if announcer.isSpeaking, trimmed == lastSpokenText {
            return
        }

        if announcer.isSpeaking {
            if isPriority {
                clearPending()
                startSpeaking(trimmed, interrupt: true)
            } else {
                pendingMessage = trimmed
                pendingPriority = isPriority
            }
            return
        }

        let cooldownRemaining = max(0, cooldownInterval - now.timeIntervalSince(lastFinishedAt))
        if cooldownRemaining > 0, !isPriority {
            pendingMessage = trimmed
            pendingPriority = isPriority
            schedulePending(after: cooldownRemaining)
            return
        }

        startSpeaking(trimmed, interrupt: true)
    }

    func stop() {
        clearPending()
        announcer.stop()
    }

    private func startSpeaking(_ text: String, interrupt: Bool) {
        lastSpokenText = text
        lastSpokenAt = Date()
        announcer.speak(text, debounce: false, interrupt: interrupt)
    }

    private func handleFinished() {
        lastFinishedAt = Date()
        guard let pendingMessage else { return }
        let priority = pendingPriority
        clearPending()
        let cooldownRemaining = max(0, cooldownInterval - Date().timeIntervalSince(lastFinishedAt))
        if cooldownRemaining > 0, !priority {
            schedulePending(after: cooldownRemaining, message: pendingMessage)
        } else {
            startSpeaking(pendingMessage, interrupt: true)
        }
    }

    private func schedulePending(after delay: TimeInterval, message: String? = nil) {
        pendingWork?.cancel()
        let messageToSpeak = message ?? pendingMessage
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.announcer.isSpeaking else { return }
            if let messageToSpeak {
                self.pendingMessage = nil
                self.pendingPriority = false
                self.pendingWork = nil
                self.startSpeaking(messageToSpeak, interrupt: true)
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func clearPending() {
        pendingWork?.cancel()
        pendingWork = nil
        pendingMessage = nil
        pendingPriority = false
    }

    private func isHighPriority(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("do not walk") || lower.contains("don't walk") {
            return true
        }
        let keywords = ["stairs", "car", "vehicle", "bus", "truck"]
        return keywords.contains { lower.contains($0) }
    }
}

struct DiagnosticsInfo {
    var fps: Double = 0
    var inferenceMs: Double = 0
    var topDetections: [String] = []
    var computeUnits: String = "N/A"
    var usesNeuralEngine: Bool = false
    var modelName: String = "N/A"
}

final class DiagnosticsTracker {
    private var timestamps: [CFTimeInterval] = []

    func updateFPS() -> Double {
        let now = CACurrentMediaTime()
        timestamps.append(now)
        timestamps = timestamps.filter { now - $0 < 1.0 }
        return Double(timestamps.count)
    }
}

// Drop .mlmodel files into Xcode; they are compiled to .mlmodelc at build.
// Expected model names in the app bundle:
// - yolov8n.mlmodelc
// - CurrencyClassifier.mlmodelc
// - CrosswalkSignalClassifier.mlmodelc
final class VisionCoreMLPipeline {
    struct ModelInfo {
        let name: String
        let vnModel: VNCoreMLModel
        let computeUnits: MLComputeUnits
        let description: MLModelDescription
        let usesNeuralEngine: Bool
    }

    static func loadModel(named name: String) -> ModelInfo? {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let bundle = Bundle.main
        let moduleCandidates = [
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        ].compactMap { $0 }
        let classCandidates = moduleCandidates.map { "\($0).\(name)" } + [name]

        var model: MLModel?
        if let url = bundle.url(forResource: name, withExtension: "mlmodelc") {
            print("[VisionCoreMLPipeline] Loading model: \(name)")
            print("[VisionCoreMLPipeline] Model path: \(url.path)")
            print("[VisionCoreMLPipeline] ComputeUnits: \(config.computeUnits)")
            for className in classCandidates {
                if let modelType = NSClassFromString(className) as? MLModel.Type {
                    model = try? modelType.init(contentsOf: url, configuration: config)
                    if model != nil {
                        print("[VisionCoreMLPipeline] Loaded generated class: \(className)")
                        break
                    }
                }
            }
            if model == nil {
                model = try? MLModel(contentsOf: url, configuration: config)
            }
        } else {
            print("[VisionCoreMLPipeline] Model not found: \(name).mlmodelc")
            print("[VisionCoreMLPipeline] Model load success: false")
            return nil
        }
        guard let model else {
            print("[VisionCoreMLPipeline] Model load failed: \(name)")
            print("[VisionCoreMLPipeline] Model load success: false")
            return nil
        }
        let vnModel = try? VNCoreMLModel(for: model)
        guard let vnModel else {
            print("[VisionCoreMLPipeline] VNCoreMLModel creation failed: \(name)")
            print("[VisionCoreMLPipeline] Model load success: false")
            return nil
        }
        let usesNeuralEngine = (config.computeUnits == .all || config.computeUnits == .cpuAndNeuralEngine)
        print("[VisionCoreMLPipeline] Loaded model \(name): \(model.modelDescription)")
        print("[VisionCoreMLPipeline] ComputeUnits selected: \(config.computeUnits)")
        print("[VisionCoreMLPipeline] Model load success: true")
        return ModelInfo(
            name: name,
            vnModel: vnModel,
            computeUnits: config.computeUnits,
            description: model.modelDescription,
            usesNeuralEngine: usesNeuralEngine
        )
    }

    static func computeUnitsDescription(_ units: MLComputeUnits) -> String {
        switch units {
        case .all: return "CPU+GPU+Neural Engine"
        case .cpuOnly: return "CPU"
        case .cpuAndGPU: return "CPU+GPU"
        case .cpuAndNeuralEngine: return "CPU+Neural Engine"
        @unknown default: return "Unknown"
        }
    }
}

final class ObjectDetectionViewModel: ObservableObject {
    @Published var statusText: String = "Loading object detector..."
    @Published var diagnostics = DiagnosticsInfo()

    private let queue = DispatchQueue(label: "echosight.object.detect", qos: .userInitiated)
    private var isProcessing = false
    private var lastProcess = Date.distantPast
    private let tracker = DiagnosticsTracker()
    private var request: VNCoreMLRequest?
    private var modelInfo: VisionCoreMLPipeline.ModelInfo?

    init() {
        loadModel()
    }

    private func loadModel() {
        modelInfo = VisionCoreMLPipeline.loadModel(named: "yolov8n")
        if let modelInfo {
            let request = VNCoreMLRequest(model: modelInfo.vnModel) { [weak self] request, _ in
                self?.handleResults(request: request)
            }
            request.imageCropAndScaleOption = .scaleFill
            self.request = request
            diagnostics.computeUnits = VisionCoreMLPipeline.computeUnitsDescription(modelInfo.computeUnits)
            diagnostics.usesNeuralEngine = modelInfo.usesNeuralEngine
            diagnostics.modelName = modelInfo.name
            setStatus("Looking for objects...")
        } else {
            diagnostics.computeUnits = "Model missing"
            diagnostics.usesNeuralEngine = false
            diagnostics.modelName = "yolov8n"
            setStatus("Model missing: yolov8n.mlmodelc")
        }
    }

    func process(sampleBuffer: CMSampleBuffer) {
        guard shouldProcess() else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let request else { return }
        isProcessing = true
        let start = CACurrentMediaTime()

        queue.async { [weak self] in
            defer { self?.isProcessing = false }
            guard let self else { return }
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
            try? handler.perform([request])
            let elapsed = (CACurrentMediaTime() - start) * 1000
            DispatchQueue.main.async {
                self.diagnostics.inferenceMs = elapsed
                self.diagnostics.fps = self.tracker.updateFPS()
            }
        }
    }

    private func handleResults(request: VNRequest) {
        let objectResults = request.results as? [VNRecognizedObjectObservation] ?? []
        let classResults = request.results as? [VNClassificationObservation] ?? []
        let featureResults = request.results?.compactMap { $0 as? VNCoreMLFeatureValueObservation } ?? []

        if let best = objectResults.first {
            let label = best.labels.first?.identifier.replacingOccurrences(of: "_", with: " ") ?? "Object"
            let position = positionDescription(for: best.boundingBox)
            setStatus("\(label.capitalized) \(position)")
            updateTopDetections(
                objectResults.map { obs in
                    let name = obs.labels.first?.identifier ?? "Object"
                    let conf = obs.labels.first?.confidence ?? 0
                    return "\(name) \(Int(conf * 100))%"
                }
            )
            return
        }

        if let feature = featureResults.first {
            let detections = YOLOPostProcessor.decode(observation: feature)
            if let best = detections.first {
                let position = positionDescription(for: best.rect)
                setStatus("\(best.label.capitalized) \(position)")
                updateTopDetections(
                    detections.prefix(3).map { det in
                        "\(det.label) \(Int(det.confidence * 100))%"
                    }
                )
                return
            }
        }

        if let bestClass = classResults.first {
            let label = bestClass.identifier.replacingOccurrences(of: "_", with: " ")
            setStatus("\(label.capitalized) ahead")
            updateTopDetections(classResults.prefix(3).map { "\($0.identifier) \(Int($0.confidence * 100))%" })
            return
        }

        setStatus("No objects detected")
        updateTopDetections([])
    }

    private func updateTopDetections(_ detections: [String]) {
        DispatchQueue.main.async {
            self.diagnostics.topDetections = detections
        }
    }

    private func positionDescription(for box: CGRect) -> String {
        let x = box.midX
        if x < 0.33 { return "on the left" }
        if x > 0.66 { return "on the right" }
        return "ahead"
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusText = text
        }
    }

    private func shouldProcess() -> Bool {
        guard !isProcessing else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastProcess) > 0.2 else { return false }
        lastProcess = now
        return true
    }
}

final class TextReaderViewModel: ObservableObject {
    @Published var recognizedText: String = "Recognized text will appear here."
    @Published var statusText: String = "Ready"
    private let queue = DispatchQueue(label: "echosight.text.read")
    private var latestBuffer: CVPixelBuffer?

    func update(sampleBuffer: CMSampleBuffer) {
        latestBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    }

    func capture() {
        guard let buffer = latestBuffer else {
            setStatus("No camera frame available")
            return
        }
        setStatus("Recognizing text...")
        queue.async { [weak self] in
            guard let self else { return }
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let combined = lines.joined(separator: "\n")
                DispatchQueue.main.async {
                    self.recognizedText = combined.isEmpty ? "No text detected." : combined
                    self.statusText = "Done"
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
            try? handler.perform([request])
        }
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusText = text
        }
    }
}

final class CurrencyIdentifierViewModel: ObservableObject {
    @Published var statusText: String = "Detected: —"
    @Published var diagnostics = DiagnosticsInfo()

    private let queue = DispatchQueue(label: "echosight.currency.identify", qos: .userInitiated)
    private var latestBuffer: CVPixelBuffer?
    private var isProcessing = false
    private var lastProcess = Date.distantPast
    private let tracker = DiagnosticsTracker()
    private var request: VNCoreMLRequest?
    private var modelInfo: VisionCoreMLPipeline.ModelInfo?
    private var lastPrediction: String = ""
    private var lastAnnounced: String = ""
    private var stableFrames: Int = 0
    private let requiredStableFrames: Int = 3

    init() {
        loadModel()
    }

    private func loadModel() {
        modelInfo = VisionCoreMLPipeline.loadModel(named: "CurrencyClassifier")
        if let modelInfo {
            let request = VNCoreMLRequest(model: modelInfo.vnModel) { [weak self] request, _ in
                self?.handleResults(request: request)
            }
            request.imageCropAndScaleOption = .centerCrop
            self.request = request
            diagnostics.computeUnits = VisionCoreMLPipeline.computeUnitsDescription(modelInfo.computeUnits)
            diagnostics.usesNeuralEngine = modelInfo.usesNeuralEngine
            diagnostics.modelName = modelInfo.name
        } else {
            diagnostics.computeUnits = "Model missing"
            diagnostics.usesNeuralEngine = false
            diagnostics.modelName = "CurrencyClassifier"
            setStatus("Model missing: CurrencyClassifier.mlmodelc")
        }
    }

    func update(sampleBuffer: CMSampleBuffer) {
        latestBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        processLatestIfNeeded()
    }

    private func processLatestIfNeeded() {
        guard let buffer = latestBuffer, shouldProcess() else { return }
        isProcessing = true
        let start = CACurrentMediaTime()
        queue.async { [weak self] in
            defer { self?.isProcessing = false }
            guard let self else { return }
            if let request = self.request {
                let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
                try? handler.perform([request])
            } else {
                self.performOCRFallback(on: buffer)
            }
            let elapsed = (CACurrentMediaTime() - start) * 1000
            DispatchQueue.main.async {
                self.diagnostics.inferenceMs = elapsed
                self.diagnostics.fps = self.tracker.updateFPS()
            }
        }
    }

    private func handleResults(request: VNRequest) {
        let results = (request.results as? [VNClassificationObservation]) ?? []
        guard let best = results.first else {
            setStatus("Detected: —")
            updateTopDetections([])
            lastPrediction = ""
            lastAnnounced = ""
            stableFrames = 0
            return
        }
        let label = best.identifier.replacingOccurrences(of: "_", with: " ")
        if label == lastPrediction {
            stableFrames += 1
        } else {
            lastPrediction = label
            stableFrames = 1
        }
        if stableFrames >= requiredStableFrames, label != lastAnnounced {
            lastAnnounced = label
            setStatus("Detected: \(label)")
        }
        updateTopDetections(results.prefix(3).map { "\($0.identifier) \(Int($0.confidence * 100))%" })
    }

    private func performOCRFallback(on buffer: CVPixelBuffer) {
        let request = VNRecognizeTextRequest { [weak self] request, _ in
            guard let self else { return }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let combined = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            let detected = self.detectDenomination(in: combined)
            self.setStatus(detected)
            self.updateTopDetections(["OCR fallback"])
        }
        request.recognitionLevel = .fast
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
        try? handler.perform([request])
    }

    private func detectDenomination(in text: String) -> String {
        let normalized = text.replacingOccurrences(of: " ", with: "")
        let candidates = ["100", "50", "20", "10", "5", "1"]
        for value in candidates {
            if normalized.contains(value) {
                return "Detected: $\(value)"
            }
        }
        return "Detected: —"
    }

    private func updateTopDetections(_ detections: [String]) {
        DispatchQueue.main.async {
            self.diagnostics.topDetections = detections
        }
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusText = text
        }
    }

    private func shouldProcess() -> Bool {
        guard !isProcessing else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastProcess) > 0.8 else { return false }
        lastProcess = now
        return true
    }
}

final class PeopleDetectionViewModel: ObservableObject {
    @Published var statusText: String = "No people detected"
    @Published var diagnostics = DiagnosticsInfo()

    private let queue = DispatchQueue(label: "echosight.people.detect", qos: .userInitiated)
    private var isProcessing = false
    private var lastProcess = Date.distantPast
    private let tracker = DiagnosticsTracker()

    func process(sampleBuffer: CMSampleBuffer) {
        guard shouldProcess() else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true
        let start = CACurrentMediaTime()
        queue.async { [weak self] in
            defer { self?.isProcessing = false }
            guard let self else { return }
            let request = VNDetectHumanRectanglesRequest { request, _ in
                let people = (request.results as? [VNHumanObservation]) ?? []
                self.updateStatus(from: people)
            }
            request.upperBodyOnly = false
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
            try? handler.perform([request])
            let elapsed = (CACurrentMediaTime() - start) * 1000
            DispatchQueue.main.async {
                self.diagnostics.inferenceMs = elapsed
                self.diagnostics.fps = self.tracker.updateFPS()
                self.diagnostics.computeUnits = "Vision"
                self.diagnostics.usesNeuralEngine = false
                self.diagnostics.modelName = "VNDetectHumanRectangles"
            }
        }
    }

    private func updateStatus(from observations: [VNHumanObservation]) {
        guard !observations.isEmpty else {
            setStatus("No people detected")
            DispatchQueue.main.async {
                self.diagnostics.topDetections = []
            }
            return
        }
        let positions = observations.map { $0.boundingBox.midX }
        let left = positions.filter { $0 < 0.33 }.count
        let right = positions.filter { $0 > 0.66 }.count
        let center = observations.count - left - right
        var parts: [String] = []
        if left > 0 { parts.append("\(left) left") }
        if center > 0 { parts.append("\(center) ahead") }
        if right > 0 { parts.append("\(right) right") }
        let summary = parts.joined(separator: ", ")
        setStatus("People: \(summary)")
        DispatchQueue.main.async {
            self.diagnostics.topDetections = ["People: \(summary)"]
        }
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusText = text
        }
    }

    private func shouldProcess() -> Bool {
        guard !isProcessing else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastProcess) > 0.8 else { return false }
        lastProcess = now
        return true
    }
}

final class CrosswalkSignalViewModel: ObservableObject {
    @Published var statusText: String = "Signal: Unknown"
    @Published var diagnostics = DiagnosticsInfo()

    private let queue = DispatchQueue(label: "echosight.crosswalk.detect", qos: .userInitiated)
    private var isProcessing = false
    private var lastProcess = Date.distantPast
    private let tracker = DiagnosticsTracker()
    private var request: VNCoreMLRequest?
    private var modelInfo: VisionCoreMLPipeline.ModelInfo?

    init() {
        loadModel()
    }

    private func loadModel() {
        modelInfo = VisionCoreMLPipeline.loadModel(named: "CrosswalkSignalClassifier")
        if let modelInfo {
            let request = VNCoreMLRequest(model: modelInfo.vnModel) { [weak self] request, _ in
                self?.handleResults(request: request)
            }
            request.imageCropAndScaleOption = .centerCrop
            self.request = request
            diagnostics.computeUnits = VisionCoreMLPipeline.computeUnitsDescription(modelInfo.computeUnits)
            diagnostics.usesNeuralEngine = modelInfo.usesNeuralEngine
            diagnostics.modelName = modelInfo.name
        } else {
            diagnostics.computeUnits = "Model missing"
            diagnostics.usesNeuralEngine = false
            diagnostics.modelName = "CrosswalkSignalClassifier"
            setStatus("Model missing: CrosswalkSignalClassifier.mlmodelc")
        }
    }

    func process(sampleBuffer: CMSampleBuffer) {
        guard shouldProcess() else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let request else { return }
        isProcessing = true
        let start = CACurrentMediaTime()
        queue.async { [weak self] in
            defer { self?.isProcessing = false }
            guard let self else { return }
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
            try? handler.perform([request])
            let elapsed = (CACurrentMediaTime() - start) * 1000
            DispatchQueue.main.async {
                self.diagnostics.inferenceMs = elapsed
                self.diagnostics.fps = self.tracker.updateFPS()
            }
        }
    }

    private func handleResults(request: VNRequest) {
        let results = (request.results as? [VNClassificationObservation]) ?? []
        guard let best = results.first else {
            setStatus("Signal: Unknown")
            updateTopDetections([])
            return
        }
        let label = best.identifier.lowercased()
        let status: String
        if label.contains("walk") && !label.contains("dont") && !label.contains("don't") {
            status = "Walk"
        } else if label.contains("dont") || label.contains("don't") || label.contains("no") {
            status = "Do Not Walk"
        } else {
            status = best.identifier.replacingOccurrences(of: "_", with: " ")
        }
        setStatus("Signal: \(status)")
        updateTopDetections(results.prefix(3).map { "\($0.identifier) \(Int($0.confidence * 100))%" })
    }

    private func updateTopDetections(_ detections: [String]) {
        DispatchQueue.main.async {
            self.diagnostics.topDetections = detections
        }
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusText = text
        }
    }

    private func shouldProcess() -> Bool {
        guard !isProcessing else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastProcess) > 0.3 else { return false }
        lastProcess = now
        return true
    }
}

final class PathGuidanceViewModel: ObservableObject {
    @Published var statusText: String = "Guidance: —"
    @Published var diagnostics = DiagnosticsInfo()

    private let queue = DispatchQueue(label: "echosight.path.guidance", qos: .userInitiated)
    private var isProcessing = false
    private var lastProcess = Date.distantPast
    private let tracker = DiagnosticsTracker()

    func process(sampleBuffer: CMSampleBuffer) {
        guard shouldProcess() else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true
        let start = CACurrentMediaTime()
        queue.async { [weak self] in
            defer { self?.isProcessing = false }
            guard let self else { return }
            let left = self.averageLuma(in: buffer, region: CGRect(x: 0.0, y: 0.3, width: 0.45, height: 0.4))
            let right = self.averageLuma(in: buffer, region: CGRect(x: 0.55, y: 0.3, width: 0.45, height: 0.4))
            let status: String
            if abs(left - right) < 10 {
                status = "Guidance: Ahead"
            } else if left < right {
                status = "Guidance: Move right"
            } else {
                status = "Guidance: Move left"
            }
            self.setStatus(status)
            let elapsed = (CACurrentMediaTime() - start) * 1000
            DispatchQueue.main.async {
                self.diagnostics.inferenceMs = elapsed
                self.diagnostics.fps = self.tracker.updateFPS()
                self.diagnostics.computeUnits = "Heuristic"
                self.diagnostics.usesNeuralEngine = false
                self.diagnostics.modelName = "PathGuidance (Heuristic)"
                self.diagnostics.topDetections = [status]
            }
        }
    }

    private func averageLuma(in buffer: CVPixelBuffer, region: CGRect) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let startX = Int(Double(width) * region.origin.x)
        let startY = Int(Double(height) * region.origin.y)
        let endX = Int(Double(width) * (region.origin.x + region.size.width))
        let endY = Int(Double(height) * (region.origin.y + region.size.height))
        let step = 8
        var sum: Double = 0
        var count: Double = 0
        for y in stride(from: startY, to: endY, by: step) {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: startX, to: endX, by: step) {
                let pixel = row.advanced(by: x * 4)
                let b = Double(pixel[0])
                let g = Double(pixel[1])
                let r = Double(pixel[2])
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                sum += luma
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return sum / count
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusText = text
        }
    }

    private func shouldProcess() -> Bool {
        guard !isProcessing else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastProcess) > 0.7 else { return false }
        lastProcess = now
        return true
    }
}
