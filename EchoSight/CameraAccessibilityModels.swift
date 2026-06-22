import AVFoundation
import Combine
import CoreML
import QuartzCore
import SwiftUI
import Vision

// CameraAccessibilityModels.swift contains the non-UI logic for camera tools.
// It groups speech feedback, model loading, diagnostics, object detection,
// OCR, currency reading, people detection, crosswalk status, and path guidance.

// Speaks short assistive messages with Apple's AVSpeechSynthesizer.
// This powers audio feedback like "Person ahead" or "Detected: $20".
final class SpeechAnnouncer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    // Shared instance is available for simple screens that do not need separate control.
    static let shared = SpeechAnnouncer()

    // Apple's speech engine. It queues AVSpeechUtterance objects.
    private let synthesizer = AVSpeechSynthesizer()
    // Debounce state prevents repeated frame-by-frame announcements.
    private var lastPhrase: String = ""
    private var lastSpokenAt: Date = .distantPast
    private let debounceInterval: TimeInterval = 1.8
    // Stored so speech can restart with new slider settings.
    private var lastSpokenText: String = ""
    // Lets AnnouncementController know when speech finished and pending text can run.
    var onQueueFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func announce(_ phrase: String) {
        // Camera pages call this for short status phrases.
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
        // Skip empty text so the synthesizer queue stays clean.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastSpokenText = trimmed
        let now = Date()
        // If the same phrase was just spoken, do not repeat it.
        if debounce, trimmed == lastPhrase, now.timeIntervalSince(lastSpokenAt) < debounceInterval {
            return
        }
        lastPhrase = trimmed
        lastSpokenAt = now

        prepareAudioSessionForSpeech()

        let sentences = splitSentences(from: trimmed)
        let voice = preferredVoice()
        let settings = SpeechSettings.load()
        // Page-specific values override saved settings only for this call.
        let finalRate = rate ?? settings.rate
        let finalPitch = pitch ?? settings.pitch
        let finalVolume = volume ?? settings.volume

        if interrupt {
            // Stop stale speech before announcing a new detection.
            synthesizer.stopSpeaking(at: .immediate)
        }
        for sentence in sentences {
            // Sentence splitting gives clearer pauses for longer OCR text.
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
        // Used by sliders so changes apply immediately while speech is active.
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
        // Configure audio so spoken feedback can mix with or duck other audio.
        let session = AVAudioSession.sharedInstance()
        let preferredOptions: AVAudioSession.CategoryOptions = [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        let fallbackOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]

        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: preferredOptions)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            do {
                // Fallback is less specialized but more likely to succeed.
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
        // Split on punctuation/newlines so long text is spoken in manageable chunks.
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
        // Respect Settings voice choice first, otherwise match the device locale.
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
        // Prefer enhanced voices when available because they sound more natural.
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

// Stored speech preferences shared by settings and all read-aloud tools.
struct SpeechSettings {
    // Centralized UserDefaults keys keep SettingsPage and SpeechAnnouncer aligned.
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
        // Defaults keep speech usable the first time the app launches.
        let defaults = UserDefaults.standard
        let voice = defaults.string(forKey: voiceIdentifierKey) ?? autoVoiceIdentifier
        let rate = defaults.object(forKey: rateKey) as? Double ?? 0.5
        let pitch = defaults.object(forKey: pitchKey) as? Double ?? 1.0
        let volume = defaults.object(forKey: volumeKey) as? Double ?? 0.9
        return SpeechSettings(voiceIdentifier: voice, rate: rate, pitch: pitch, volume: volume)
    }
}

// Prevents rapid repeated announcements from stacking up while frames stream in.
final class AnnouncementController: ObservableObject {
    // Wrapped announcer does the actual speech. This class decides when to speak.
    private let announcer: SpeechAnnouncer
    // Same text must wait this long before being announced again.
    private let debounceInterval: TimeInterval = 2.6
    // Different non-priority messages are spaced out for clarity.
    private let cooldownInterval: TimeInterval = 1.8
    private var lastSpokenText: String = ""
    private var lastSpokenAt: Date = .distantPast
    private var lastFinishedAt: Date = .distantPast
    // Pending message stores one delayed announcement while the synthesizer is busy.
    private var pendingMessage: String?
    private var pendingPriority: Bool = false
    private var pendingWork: DispatchWorkItem?

    init(announcer: SpeechAnnouncer = SpeechAnnouncer()) {
        self.announcer = announcer
        announcer.onQueueFinished = { [weak self] in
            // When speech finishes, the controller decides whether pending text can play.
            self?.handleFinished()
        }
    }

    func announce(_ text: String, priority: Bool? = nil) {
        // Camera model strings are cleaned before any speech scheduling.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let isPriority = priority ?? isHighPriority(trimmed)
        let now = Date()
        // Ignore repeated text inside the debounce window.
        if trimmed == lastSpokenText, now.timeIntervalSince(lastSpokenAt) < debounceInterval {
            return
        }
        // If the same thing is still being spoken, do not queue a duplicate.
        if announcer.isSpeaking, trimmed == lastSpokenText {
            return
        }

        if announcer.isSpeaking {
            if isPriority {
                // Safety-related messages interrupt current speech.
                clearPending()
                startSpeaking(trimmed, interrupt: true)
            } else {
                // Non-priority text waits its turn.
                pendingMessage = trimmed
                pendingPriority = isPriority
            }
            return
        }

        let cooldownRemaining = max(0, cooldownInterval - now.timeIntervalSince(lastFinishedAt))
        if cooldownRemaining > 0, !isPriority {
            // Speech just ended, so schedule this after the cooldown.
            pendingMessage = trimmed
            pendingPriority = isPriority
            schedulePending(after: cooldownRemaining)
            return
        }

        startSpeaking(trimmed, interrupt: true)
    }

    func stop() {
        // Used when a page disappears so no old messages keep talking.
        clearPending()
        announcer.stop()
    }

    private func startSpeaking(_ text: String, interrupt: Bool) {
        // Save spoken text for future duplicate/cooldown checks.
        lastSpokenText = text
        lastSpokenAt = Date()
        announcer.speak(text, debounce: false, interrupt: interrupt)
    }

    private func handleFinished() {
        // Mark the finish time for cooldown math.
        lastFinishedAt = Date()
        guard let pendingMessage else { return }
        let priority = pendingPriority
        clearPending()
        let cooldownRemaining = max(0, cooldownInterval - Date().timeIntervalSince(lastFinishedAt))
        if cooldownRemaining > 0, !priority {
            // Pending non-priority text still obeys cooldown.
            schedulePending(after: cooldownRemaining, message: pendingMessage)
        } else {
            startSpeaking(pendingMessage, interrupt: true)
        }
    }

    private func schedulePending(after delay: TimeInterval, message: String? = nil) {
        // Replace any older delayed work with the newest pending message.
        pendingWork?.cancel()
        let messageToSpeak = message ?? pendingMessage
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // If speech restarted, drop this work item and let the next change reschedule.
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
        // Cancel delayed speech and clear pending flags.
        pendingWork?.cancel()
        pendingWork = nil
        pendingMessage = nil
        pendingPriority = false
    }

    private func isHighPriority(_ text: String) -> Bool {
        // Words that imply immediate action are treated as priority speech.
        let lower = text.lowercased()
        if lower.contains("do not walk") || lower.contains("don't walk") {
            return true
        }
        let keywords = ["stairs", "car", "vehicle", "bus", "truck"]
        return keywords.contains { lower.contains($0) }
    }
}

// Optional developer-facing values shown only when "Show diagnostics" is enabled.
struct DiagnosticsInfo {
    // Values shown by DiagnosticsOverlay. They are optional developer/demo data,
    // not required for normal user operation.
    var fps: Double = 0
    var inferenceMs: Double = 0
    var topDetections: [String] = []
    var computeUnits: String = "N/A"
    var usesNeuralEngine: Bool = false
    var modelName: String = "N/A"
}

// Counts recent inference timestamps to estimate frames per second.
final class DiagnosticsTracker {
    // One-second sliding window of inference times.
    private var timestamps: [CFTimeInterval] = []

    func updateFPS() -> Double {
        // Count how many frames completed in the last second.
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
// Central place for loading compiled Core ML models from the app bundle.
// It prefers CPU/GPU/Neural Engine so supported iPhones use acceleration.
final class VisionCoreMLPipeline {
    struct ModelInfo {
        // Keep model metadata together so view models can display diagnostics.
        let name: String
        let vnModel: VNCoreMLModel
        let computeUnits: MLComputeUnits
        let description: MLModelDescription
        let usesNeuralEngine: Bool
    }

    static func loadModel(named name: String) -> ModelInfo? {
        // .all lets Core ML choose CPU, GPU, or Neural Engine depending on device.
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let bundle = Bundle.main
        // Generated Core ML classes may be namespaced with module/bundle names.
        let moduleCandidates = [
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        ].compactMap { $0 }
        let classCandidates = moduleCandidates.map { "\($0).\(name)" } + [name]

        var model: MLModel?
        if let url = bundle.url(forResource: name, withExtension: "mlmodelc") {
            // Xcode compiles .mlmodel/.mlpackage into .mlmodelc in the app bundle.
            print("[VisionCoreMLPipeline] Loading model: \(name)")
            print("[VisionCoreMLPipeline] Model path: \(url.path)")
            print("[VisionCoreMLPipeline] ComputeUnits: \(config.computeUnits)")
            for className in classCandidates {
                // Prefer generated model classes when Xcode created one.
                if let modelType = NSClassFromString(className) as? MLModel.Type {
                    model = try? modelType.init(contentsOf: url, configuration: config)
                    if model != nil {
                        print("[VisionCoreMLPipeline] Loaded generated class: \(className)")
                        break
                    }
                }
            }
            if model == nil {
                // Generic MLModel loading works even without a generated Swift class.
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
            // Vision needs VNCoreMLModel to run the model on camera frames.
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
        // Human-readable labels for the diagnostics overlay.
        switch units {
        case .all: return "CPU+GPU+Neural Engine"
        case .cpuOnly: return "CPU"
        case .cpuAndGPU: return "CPU+GPU"
        case .cpuAndNeuralEngine: return "CPU+Neural Engine"
        @unknown default: return "Unknown"
        }
    }
}

// Live object detector:
// 1. YOLO finds common objects and their rough left/right/ahead positions.
// 2. VNClassifyImageRequest fills in broader labels when YOLO is unsure.
final class ObjectDetectionViewModel: ObservableObject {
    // statusText is the only thing the page needs for the main result card.
    @Published var statusText: String = "Loading object detector..."
    // diagnostics is optional UI for debugging performance/model behavior.
    @Published var diagnostics = DiagnosticsInfo()
    var diagnosticsEnabled = false

    // Vision/Core ML work happens off the main thread.
    private let queue = DispatchQueue(label: "echosight.object.detect", qos: .userInitiated)
    // isProcessing prevents overlapping Vision requests.
    private var isProcessing = false
    // lastProcess throttles the stream so the phone stays smooth.
    private var lastProcess = Date.distantPast
    private let tracker = DiagnosticsTracker()
    // Main YOLO request plus a broader scene classifier fallback.
    private var request: VNCoreMLRequest?
    private var sceneRequest: VNClassifyImageRequest?
    private var modelInfo: VisionCoreMLPipeline.ModelInfo?
    // Minimum confidence for accepting object labels.
    private let confidenceThreshold = 0.30
    // Stable frames reduce one-frame false positives.
    private let requiredStableFrames = 2
    private let requiredMissedFrames = 4
    // Scene fallback runs less often because it is only a backup label.
    private let sceneClassificationInterval: TimeInterval = 1.1
    private let detectionStaleInterval: TimeInterval = 1.3
    private let sceneConfidenceThreshold = 0.18
    // Tracks whether the same object+position repeats over time.
    private var pendingDetectionKey = ""
    private var stableDetectionFrames = 0
    private var lastPublishedDetectionKey = ""
    private var missedDetectionFrames = 0
    private var lastSceneProcess = Date.distantPast
    private var lastReliableDetectionAt = Date.distantPast

    init() {
        loadModel()
        loadSceneFallback()
    }

    private func loadModel() {
        // Try to load the bundled YOLO model and wrap it in a Vision request.
        modelInfo = VisionCoreMLPipeline.loadModel(named: "yolov8n")
        if let modelInfo {
            let request = VNCoreMLRequest(model: modelInfo.vnModel) { [weak self] request, _ in
                self?.handleResults(request: request)
            }
            // scaleFit preserves the full frame, which keeps left/right position useful.
            request.imageCropAndScaleOption = .scaleFit
            self.request = request
            diagnostics.computeUnits = VisionCoreMLPipeline.computeUnitsDescription(modelInfo.computeUnits)
            diagnostics.usesNeuralEngine = modelInfo.usesNeuralEngine
            diagnostics.modelName = modelInfo.name
            setStatus("Looking for objects...")
        } else {
            // Missing model should be visible in the UI instead of silently failing.
            diagnostics.computeUnits = "Model missing"
            diagnostics.usesNeuralEngine = false
            diagnostics.modelName = "yolov8n"
            setStatus("Model missing: yolov8n.mlmodelc")
        }
    }

    private func loadSceneFallback() {
        // Built-in Vision scene labels help when YOLO is uncertain or missing.
        let request = VNClassifyImageRequest { [weak self] request, _ in
            self?.handleSceneResults(request: request)
        }
        self.sceneRequest = request
    }

    func process(sampleBuffer: CMSampleBuffer) {
        // This is called repeatedly by CameraManager, so all guards are cheap.
        guard shouldProcess() else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let requests = requestsForCurrentFrame()
        guard !requests.isEmpty else { return }
        isProcessing = true
        let start = CACurrentMediaTime()

        queue.async { [weak self] in
            // Always clear isProcessing when the background request finishes.
            defer { self?.isProcessing = false }
            guard let self else { return }
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
            try? handler.perform(requests)
            let elapsed = (CACurrentMediaTime() - start) * 1000
            if self.diagnosticsEnabled {
                DispatchQueue.main.async {
                    // Only publish diagnostics when the overlay is on.
                    self.diagnostics.inferenceMs = elapsed
                    self.diagnostics.fps = self.tracker.updateFPS()
                }
            }
        }
    }

    private func requestsForCurrentFrame() -> [VNRequest] {
        // YOLO runs on sampled frames. The broader scene classifier only runs
        // when recent YOLO detections are stale, which protects smoothness.
        var requests: [VNRequest] = []
        if let request {
            requests.append(request)
        }
        let now = Date()
        if let sceneRequest,
           now.timeIntervalSince(lastSceneProcess) >= sceneClassificationInterval,
           now.timeIntervalSince(lastReliableDetectionAt) >= detectionStaleInterval {
            lastSceneProcess = now
            requests.append(sceneRequest)
        }
        return requests
    }

    private func handleResults(request: VNRequest) {
        // Vision may return several result shapes depending on the model export.
        // We handle recognized objects, YOLO tensors, and classifications.
        let objectResults = request.results as? [VNRecognizedObjectObservation] ?? []
        let classResults = request.results as? [VNClassificationObservation] ?? []
        let featureResults = request.results?.compactMap { $0 as? VNCoreMLFeatureValueObservation } ?? []

        let recognizedObjects = objectResults.compactMap { observation -> DetectedObject? in
            // VNRecognizedObjectObservation path is used by models exported with boxes.
            guard let label = observation.labels.first, Double(label.confidence) >= confidenceThreshold else {
                return nil
            }
            return DetectedObject(
                label: label.identifier,
                confidence: Double(label.confidence),
                rect: observation.boundingBox
            )
        }
        .sorted { $0.confidence > $1.confidence }

        if let best = recognizedObjects.first {
            // Best box result becomes the spoken/status result.
            missedDetectionFrames = 0
            publishStableDetection(best)
            updateTopDetections(
                recognizedObjects.prefix(4).map { formattedDetection($0) }
            )
            return
        }

        let nmsDetections = decodeNMSDetections(from: featureResults)
        if let best = nmsDetections.first {
            // Some YOLO exports return confidence/coordinate tensors needing NMS decode.
            missedDetectionFrames = 0
            publishStableDetection(best)
            updateTopDetections(nmsDetections.prefix(4).map { formattedDetection($0) })
            return
        }

        if let feature = featureResults.first {
            // Fallback decoder handles common raw YOLO tensor layouts.
            let detections = YOLOPostProcessor.decode(observation: feature, confidenceThreshold: confidenceThreshold)
            if let best = detections.first {
                missedDetectionFrames = 0
                publishStableDetection(best)
                updateTopDetections(
                    detections.prefix(4).map { formattedDetection($0) }
                )
                return
            }
        }

        if let bestClass = classResults.first, Double(bestClass.confidence) >= confidenceThreshold {
            // Classification-only model output has no box, so we use a centered rect.
            let label = bestClass.identifier.replacingOccurrences(of: "_", with: " ")
            missedDetectionFrames = 0
            publishStableDetection(
                DetectedObject(label: label, confidence: Double(bestClass.confidence), rect: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30))
            )
            updateTopDetections(classResults.prefix(4).map { "\($0.identifier) \(Int($0.confidence * 100))%" })
            return
        }

        handleMissedDetection()
    }

    private func handleSceneResults(request: VNRequest) {
        // Scene classification has no bounding box, so we treat it as "ahead".
        // It is used only as a fallback when YOLO is not confident.
        let results = ((request.results as? [VNClassificationObservation]) ?? [])
            .filter { Double($0.confidence) >= sceneConfidenceThreshold }
            .filter { !sceneLabel(from: $0.identifier).isEmpty }
            .sorted { $0.confidence > $1.confidence }

        guard Date().timeIntervalSince(lastReliableDetectionAt) >= detectionStaleInterval,
              let best = results.first else {
            return
        }

        let label = sceneLabel(from: best.identifier)
        missedDetectionFrames = 0
        publishStableDetection(
            DetectedObject(label: label, confidence: Double(best.confidence), rect: CGRect(x: 0.35, y: 0.35, width: 0.30, height: 0.30)),
            immediateConfidence: 0.45
        )
        updateTopDetections(results.prefix(4).map { "\(sceneLabel(from: $0.identifier)) \(Int($0.confidence * 100))%" })
    }

    private func decodeNMSDetections(from features: [VNCoreMLFeatureValueObservation]) -> [DetectedObject] {
        // NMS models usually expose separate confidence and coordinates outputs.
        guard let confidence = features.first(where: { $0.featureName == "confidence" }),
              let coordinates = features.first(where: { $0.featureName == "coordinates" }) else {
            return []
        }
        return YOLOPostProcessor.decodeNMS(
            confidenceObservation: confidence,
            coordinatesObservation: coordinates,
            confidenceThreshold: confidenceThreshold
        )
    }

    private func publishStableDetection(_ detection: DetectedObject, immediateConfidence: Double = 0.72) {
        // A detection must repeat or be very confident before the UI speaks it.
        // This avoids announcing flickery one-frame guesses.
        let label = detection.label.replacingOccurrences(of: "_", with: " ")
        let position = positionDescription(for: detection.rect)
        let key = "\(label.lowercased())|\(position)"
        if key == pendingDetectionKey {
            stableDetectionFrames += 1
        } else {
            pendingDetectionKey = key
            stableDetectionFrames = 1
        }

        guard stableDetectionFrames >= requiredStableFrames || detection.confidence >= immediateConfidence else { return }
        guard key != lastPublishedDetectionKey else { return }
        lastPublishedDetectionKey = key
        lastReliableDetectionAt = Date()
        setStatus("\(label.capitalized) \(position)")
    }

    private func handleMissedDetection() {
        // Require several misses before clearing the UI to avoid flicker.
        missedDetectionFrames += 1
        guard missedDetectionFrames >= requiredMissedFrames else { return }
        resetStableDetection()
        setStatus("No clear objects detected")
        updateTopDetections([])
    }

    private func resetStableDetection() {
        // Reset all stability memory when the scene is no longer reliable.
        pendingDetectionKey = ""
        stableDetectionFrames = 0
        lastPublishedDetectionKey = ""
    }

    private func sceneLabel(from identifier: String) -> String {
        // Vision scene identifiers can include comma-separated alternatives.
        let firstLabel = identifier
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? identifier
        return firstLabel.replacingOccurrences(of: "_", with: " ")
    }

    private func formattedDetection(_ detection: DetectedObject) -> String {
        // Compact string for the diagnostics overlay.
        let label = detection.label.replacingOccurrences(of: "_", with: " ")
        return "\(label) \(Int(detection.confidence * 100))%"
    }

    private func updateTopDetections(_ detections: [String]) {
        // Avoid unnecessary SwiftUI publishes when diagnostics are hidden.
        guard diagnosticsEnabled else { return }
        DispatchQueue.main.async {
            if self.diagnostics.topDetections != detections {
                self.diagnostics.topDetections = detections
            }
        }
    }

    private func positionDescription(for box: CGRect) -> String {
        // Use horizontal thirds to describe relative direction.
        let x = box.midX
        if x < 0.33 { return "on the left" }
        if x > 0.66 { return "on the right" }
        return "ahead"
    }

    private func setStatus(_ text: String) {
        // Publish on main queue because @Published drives SwiftUI.
        DispatchQueue.main.async {
            if self.statusText != text {
                self.statusText = text
            }
        }
    }

    private func shouldProcess() -> Bool {
        // Prevent overlapping inferences and cap processing to about 3 FPS.
        guard !isProcessing else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastProcess) > 0.35 else { return false }
        lastProcess = now
        return true
    }
}

// Stores the latest camera frame and runs Vision OCR only when the user taps capture.
// OCR is heavier than preview, so it is intentionally not continuous.
final class TextReaderViewModel: ObservableObject {
    // Text shown in the OCR result area.
    @Published var recognizedText: String = "Recognized text will appear here."
    @Published var statusText: String = "Ready"
    // OCR runs off the main thread because accurate text recognition can be slow.
    private let queue = DispatchQueue(label: "echosight.text.read")
    // Only the newest camera frame is kept; Capture reads whatever the camera sees now.
    private var latestBuffer: CVPixelBuffer?

    func update(sampleBuffer: CMSampleBuffer) {
        // Called continuously by CameraManager, but this only stores a frame.
        latestBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    }

    func capture() {
        // If camera startup has not delivered a frame yet, show a helpful status.
        guard let buffer = latestBuffer else {
            setStatus("No camera frame available")
            return
        }
        setStatus("Recognizing text...")
        queue.async { [weak self] in
            guard let self else { return }
            // Vision OCR runs locally on the device.
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                // Take the top candidate for each observed text line.
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let combined = lines.joined(separator: "\n")
                DispatchQueue.main.async {
                    // Publish result back on main because SwiftUI observes it.
                    self.recognizedText = combined.isEmpty ? "No text detected." : combined
                    self.statusText = "Done"
                }
            }
            // accurate mode is slower than fast mode but better for reading documents.
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
            try? handler.perform([request])
        }
    }

    private func setStatus(_ text: String) {
        // Status is @Published, so update it on the main queue.
        DispatchQueue.main.async {
            if self.statusText != text {
                self.statusText = text
            }
        }
    }
}

// Currency uses a bundled classifier if one exists. If it is missing, the app
// falls back to on-device OCR and looks for denomination words/numbers.
final class CurrencyIdentifierViewModel: ObservableObject {
    // Main human-readable result shown in the UI.
    @Published var statusText: String = "Point camera at a bill"
    @Published var diagnostics = DiagnosticsInfo()
    var diagnosticsEnabled = false

    private struct TextCandidate {
        // One OCR candidate and its confidence score.
        let text: String
        let confidence: Double
    }

    private struct DenominationPattern {
        // Denomination clues can be numeric, phrase-based, or single-word tokens.
        let label: String
        let numericTokens: [String]
        let phrases: [String]
        let wordTokens: [String]
    }

    private struct CurrencyEvidence {
        // Evidence object stores the winning denomination and why it won.
        let label: String
        let confidence: Double
        let score: Double
        let clues: [String]
    }

    private let queue = DispatchQueue(label: "echosight.currency.identify", qos: .userInitiated)
    // Latest frame is stored so processing can be throttled.
    private var latestBuffer: CVPixelBuffer?
    private var isProcessing = false
    private var lastProcess = Date.distantPast
    private let tracker = DiagnosticsTracker()
    // Custom classifier request when CurrencyClassifier exists in the app bundle.
    private var request: VNCoreMLRequest?
    private var modelInfo: VisionCoreMLPipeline.ModelInfo?
    // Stability state prevents one weak frame from being announced as a bill.
    private var lastPrediction: String = ""
    private var lastPublished: String = ""
    private var stableFrames: Int = 0
    private let requiredStableFrames: Int = 2
    private let minimumModelConfidence = 0.65
    private let minimumOCRConfidence = 0.45
    // Conservative U.S. bill patterns used by the OCR fallback.
    private let denominationPatterns: [DenominationPattern] = [
        DenominationPattern(label: "$100", numericTokens: ["100"], phrases: ["ONE HUNDRED"], wordTokens: ["HUNDRED"]),
        DenominationPattern(label: "$50", numericTokens: ["50"], phrases: [], wordTokens: ["FIFTY"]),
        DenominationPattern(label: "$20", numericTokens: ["20"], phrases: [], wordTokens: ["TWENTY"]),
        DenominationPattern(label: "$10", numericTokens: ["10"], phrases: [], wordTokens: ["TEN"]),
        DenominationPattern(label: "$5", numericTokens: ["5"], phrases: [], wordTokens: ["FIVE"]),
        DenominationPattern(label: "$2", numericTokens: ["2"], phrases: ["TWO DOLLARS"], wordTokens: ["TWO"]),
        DenominationPattern(label: "$1", numericTokens: ["1"], phrases: ["ONE DOLLAR"], wordTokens: [])
    ]

    init() {
        loadModel()
    }

    private func loadModel() {
        // Optional custom model path. If missing, OCR fallback still works.
        modelInfo = VisionCoreMLPipeline.loadModel(named: "CurrencyClassifier")
        if let modelInfo {
            let request = VNCoreMLRequest(model: modelInfo.vnModel) { [weak self] request, _ in
                self?.handleResults(request: request)
            }
            // Keep the full frame so bill corners/numbers are not cropped away.
            request.imageCropAndScaleOption = .scaleFit
            self.request = request
            diagnostics.computeUnits = VisionCoreMLPipeline.computeUnitsDescription(modelInfo.computeUnits)
            diagnostics.usesNeuralEngine = modelInfo.usesNeuralEngine
            diagnostics.modelName = modelInfo.name
        } else {
            // Missing classifier is not fatal; the fallback will still run.
            diagnostics.computeUnits = "Model missing"
            diagnostics.usesNeuralEngine = false
            diagnostics.modelName = "CurrencyClassifier"
            setStatus("Model missing: CurrencyClassifier.mlmodelc")
        }
    }

    func update(sampleBuffer: CMSampleBuffer) {
        // CameraManager calls this with throttled frames.
        latestBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        processLatestIfNeeded()
    }

    private func processLatestIfNeeded() {
        // Skip when another recognition request is still running.
        guard let buffer = latestBuffer, shouldProcess() else { return }
        isProcessing = true
        let start = CACurrentMediaTime()
        queue.async { [weak self] in
            defer { self?.isProcessing = false }
            guard let self else { return }
            if let request = self.request {
                // Run the custom classifier if available.
                let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
                try? handler.perform([request])
            } else {
                // Otherwise use Vision OCR and score denomination clues.
                self.performOCRFallback(on: buffer)
            }
            let elapsed = (CACurrentMediaTime() - start) * 1000
            if self.diagnosticsEnabled {
                DispatchQueue.main.async {
                    self.diagnostics.inferenceMs = elapsed
                    self.diagnostics.fps = self.tracker.updateFPS()
                }
            }
        }
    }

    private func handleResults(request: VNRequest) {
        // CurrencyClassifier output is expected to be classification labels.
        let results = ((request.results as? [VNClassificationObservation]) ?? [])
            .sorted { $0.confidence > $1.confidence }
        guard let best = results.first,
              Double(best.confidence) >= minimumModelConfidence,
              let label = standardizedDenominationLabel(from: best.identifier) else {
            // Avoid guessing when the model is unsure.
            setStatus("Hold bill steady")
            updateTopDetections(results.prefix(3).map { "\($0.identifier) \(Int($0.confidence * 100))%" })
            resetStableCurrency()
            return
        }
        publishStableCurrency(label: label, confidence: Double(best.confidence), source: "Model")
        updateTopDetections(results.prefix(3).map { "\($0.identifier) \(Int($0.confidence * 100))%" })
    }

    private func performOCRFallback(on buffer: CVPixelBuffer) {
        // Fallback path: read visible text/numbers from the bill.
        let request = VNRecognizeTextRequest { [weak self] request, _ in
            guard let self else { return }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let candidates = observations.flatMap { observation in
                // Top 3 gives the scorer alternatives when OCR is uncertain.
                observation.topCandidates(3).map {
                    TextCandidate(text: $0.string, confidence: Double($0.confidence))
                }
            }
            guard let evidence = self.bestCurrencyEvidence(from: candidates),
                  evidence.confidence >= self.minimumOCRConfidence else {
                // No confident bill evidence yet.
                self.setStatus("Hold bill steady")
                self.updateTopDetections(["OCR: no confident denomination"])
                self.resetStableCurrency()
                return
            }
            self.publishStableCurrency(label: evidence.label, confidence: evidence.confidence, source: "OCR")
            let clueText = evidence.clues.prefix(3).joined(separator: ", ")
            self.updateTopDetections(["OCR \(evidence.label) \(Int(evidence.confidence * 100))%", "Clues: \(clueText)"])
        }
        request.recognitionLevel = .fast
        // Correction can turn serial numbers into words, so keep raw OCR.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.015
        request.customWords = [
            // Currency vocabulary nudges OCR toward denominations and bill text.
            "ONE", "TWO", "FIVE", "TEN", "TWENTY", "FIFTY", "HUNDRED",
            "DOLLAR", "DOLLARS", "FEDERAL", "RESERVE", "TREASURY"
        ]
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
        try? handler.perform([request])
    }

    private func bestCurrencyEvidence(from candidates: [TextCandidate]) -> CurrencyEvidence? {
        // Score several OCR clues instead of trusting one random digit.
        // Example: "TWENTY" plus "FEDERAL RESERVE" is stronger than just "20".
        guard !candidates.isEmpty else { return nil }
        let combinedText = candidates.map(\.text).joined(separator: " ").uppercased()
        // Context words boost confidence only after some denomination evidence exists.
        let contextBonus = currencyContextBonus(in: combinedText)
        var bestEvidence: CurrencyEvidence?

        for pattern in denominationPatterns {
            var score = 0.0
            var clues: [String] = []

            for candidate in candidates {
                let text = candidate.text.uppercased()
                let tokens = tokens(in: text)
                let confidenceWeight = max(0.35, min(candidate.confidence, 1.0))

                for number in pattern.numericTokens where tokens.contains(number) {
                    // Numeric denomination is strong evidence.
                    score += 3.2 * confidenceWeight
                    clues.append(number)
                }
                for phrase in pattern.phrases where text.contains(phrase) {
                    // Full phrases like "ONE HUNDRED" are strong evidence.
                    score += 3.4 * confidenceWeight
                    clues.append(phrase.capitalized)
                }
                for word in pattern.wordTokens where tokens.contains(word) {
                    // Word tokens catch printed words like TWENTY or FIVE.
                    score += 2.8 * confidenceWeight
                    clues.append(word.capitalized)
                }
            }

            guard score > 0 else { continue }
            score += contextBonus
            // Convert score to a bounded confidence value for display/thresholds.
            let confidence = min(0.99, score / 7.0)
            let evidence = CurrencyEvidence(
                label: pattern.label,
                confidence: confidence,
                score: score,
                clues: Array(Set(clues)).sorted()
            )
            if bestEvidence == nil || evidence.score > bestEvidence!.score {
                bestEvidence = evidence
            }
        }

        return bestEvidence
    }

    private func currencyContextBonus(in text: String) -> Double {
        // Context words make it less likely that a random number is mistaken for money.
        let contextWords = ["UNITED", "STATES", "FEDERAL", "RESERVE", "NOTE", "TREASURY", "AMERICA", "DOLLAR", "DOLLARS"]
        let matches = contextWords.filter { text.contains($0) }.count
        return min(1.5, Double(matches) * 0.30)
    }

    private func tokens(in text: String) -> Set<String> {
        // Split on punctuation/spaces so "20." still matches token "20".
        let separators = CharacterSet.alphanumerics.inverted
        let parts = text
            .uppercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        return Set(parts)
    }

    private func standardizedDenominationLabel(from identifier: String) -> String? {
        // Normalize model labels to a consistent UI format.
        let text = identifier.uppercased().replacingOccurrences(of: "_", with: " ")
        if text.contains("100") || text.contains("HUNDRED") { return "$100" }
        if text.contains("50") || text.contains("FIFTY") { return "$50" }
        if text.contains("20") || text.contains("TWENTY") { return "$20" }
        if text.contains("10") || text.contains("TEN") { return "$10" }
        if text.contains("5") || text.contains("FIVE") { return "$5" }
        if text.contains("2") || text.contains("TWO") { return "$2" }
        if text.contains("1") || text.contains("ONE") { return "$1" }
        return nil
    }

    private func publishStableCurrency(label: String, confidence: Double, source: String) {
        // Same label across multiple frames becomes stable.
        if label == lastPrediction {
            stableFrames += 1
        } else {
            lastPrediction = label
            stableFrames = 1
        }

        guard stableFrames >= requiredStableFrames || confidence >= 0.82 else {
            // High confidence can publish sooner; otherwise show confirming state.
            setStatus("Confirming \(label)")
            return
        }
        guard label != lastPublished else { return }
        // Avoid repeating the exact same denomination over and over.
        lastPublished = label
        setStatus("Detected: \(label)")
        updateTopDetections(["\(source) \(label) \(Int(confidence * 100))%"])
    }

    private func resetStableCurrency() {
        // Clear stability memory when the view model loses confidence.
        lastPrediction = ""
        lastPublished = ""
        stableFrames = 0
    }

    private func updateTopDetections(_ detections: [String]) {
        // Diagnostics are only updated when the overlay is requested.
        guard diagnosticsEnabled else { return }
        DispatchQueue.main.async {
            if self.diagnostics.topDetections != detections {
                self.diagnostics.topDetections = detections
            }
        }
    }

    private func setStatus(_ text: String) {
        // Main-thread publish for SwiftUI safety.
        DispatchQueue.main.async {
            if self.statusText != text {
                self.statusText = text
            }
        }
    }

    private func shouldProcess() -> Bool {
        // Currency is slower than object detection because OCR/classification is heavier.
        guard !isProcessing else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastProcess) > 0.9 else { return false }
        lastProcess = now
        return true
    }
}

// Uses Apple's human-rectangle detector. It reports only relative position
// counts and does not identify faces or track people.
final class PeopleDetectionViewModel: ObservableObject {
    // User-facing result. It never includes names, faces, or identity.
    @Published var statusText: String = "No people detected"
    @Published var diagnostics = DiagnosticsInfo()
    var diagnosticsEnabled = false

    // Human rectangle detection runs in the background.
    private let queue = DispatchQueue(label: "echosight.people.detect", qos: .userInitiated)
    private var isProcessing = false
    private var lastProcess = Date.distantPast
    private let tracker = DiagnosticsTracker()

    func process(sampleBuffer: CMSampleBuffer) {
        // Guard against overlapping Vision requests and over-processing frames.
        guard shouldProcess() else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true
        let start = CACurrentMediaTime()
        queue.async { [weak self] in
            // Always clear the busy flag when this frame finishes.
            defer { self?.isProcessing = false }
            guard let self else { return }
            let request = VNDetectHumanRectanglesRequest { request, _ in
                // Observations are only body rectangles, not face recognition.
                let people = (request.results as? [VNHumanObservation]) ?? []
                self.updateStatus(from: people)
            }
            // false means look for full human rectangles when possible.
            request.upperBodyOnly = false
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
            try? handler.perform([request])
            let elapsed = (CACurrentMediaTime() - start) * 1000
            if self.diagnosticsEnabled {
                DispatchQueue.main.async {
                    self.diagnostics.inferenceMs = elapsed
                    self.diagnostics.fps = self.tracker.updateFPS()
                    self.diagnostics.computeUnits = "Vision"
                    self.diagnostics.usesNeuralEngine = false
                    self.diagnostics.modelName = "VNDetectHumanRectangles"
                }
            }
        }
    }

    private func updateStatus(from observations: [VNHumanObservation]) {
        // No rectangles means no people currently visible.
        guard !observations.isEmpty else {
            setStatus("No people detected")
            if diagnosticsEnabled {
                DispatchQueue.main.async {
                    if !self.diagnostics.topDetections.isEmpty {
                        self.diagnostics.topDetections = []
                    }
                }
            }
            return
        }
        // midX of the bounding box is enough for left/ahead/right guidance.
        let positions = observations.map { $0.boundingBox.midX }
        let left = positions.filter { $0 < 0.33 }.count
        let right = positions.filter { $0 > 0.66 }.count
        let center = observations.count - left - right
        var parts: [String] = []
        // Build compact spoken text, such as "1 left, 2 ahead".
        if left > 0 { parts.append("\(left) left") }
        if center > 0 { parts.append("\(center) ahead") }
        if right > 0 { parts.append("\(right) right") }
        let summary = parts.joined(separator: ", ")
        setStatus("People: \(summary)")
        if diagnosticsEnabled {
            DispatchQueue.main.async {
                let detections = ["People: \(summary)"]
                if self.diagnostics.topDetections != detections {
                    self.diagnostics.topDetections = detections
                }
            }
        }
    }

    private func setStatus(_ text: String) {
        // Publish on main for SwiftUI.
        DispatchQueue.main.async {
            if self.statusText != text {
                self.statusText = text
            }
        }
    }

    private func shouldProcess() -> Bool {
        // People detection is sampled below camera FPS for smoothness.
        guard !isProcessing else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastProcess) > 0.8 else { return false }
        lastProcess = now
        return true
    }
}

// Placeholder pipeline for a future crosswalk signal classifier model.
// The structure is ready for a Core ML model named CrosswalkSignalClassifier.
final class CrosswalkSignalViewModel: ObservableObject {
    // User-facing signal state.
    @Published var statusText: String = "Signal: Unknown"
    @Published var diagnostics = DiagnosticsInfo()
    var diagnosticsEnabled = false

    private let queue = DispatchQueue(label: "echosight.crosswalk.detect", qos: .userInitiated)
    private var isProcessing = false
    private var lastProcess = Date.distantPast
    private let tracker = DiagnosticsTracker()
    // Optional Core ML classifier for crosswalk signal images.
    private var request: VNCoreMLRequest?
    private var modelInfo: VisionCoreMLPipeline.ModelInfo?

    init() {
        loadModel()
    }

    private func loadModel() {
        // CrosswalkSignalClassifier can be added later without changing the UI page.
        modelInfo = VisionCoreMLPipeline.loadModel(named: "CrosswalkSignalClassifier")
        if let modelInfo {
            let request = VNCoreMLRequest(model: modelInfo.vnModel) { [weak self] request, _ in
                self?.handleResults(request: request)
            }
            // Center crop assumes the user points the camera at the signal.
            request.imageCropAndScaleOption = .centerCrop
            self.request = request
            diagnostics.computeUnits = VisionCoreMLPipeline.computeUnitsDescription(modelInfo.computeUnits)
            diagnostics.usesNeuralEngine = modelInfo.usesNeuralEngine
            diagnostics.modelName = modelInfo.name
        } else {
            // Missing model is surfaced in the status card for demo clarity.
            diagnostics.computeUnits = "Model missing"
            diagnostics.usesNeuralEngine = false
            diagnostics.modelName = "CrosswalkSignalClassifier"
            setStatus("Model missing: CrosswalkSignalClassifier.mlmodelc")
        }
    }

    func process(sampleBuffer: CMSampleBuffer) {
        // Without a model request, there is nothing to process.
        guard shouldProcess() else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let request else { return }
        isProcessing = true
        let start = CACurrentMediaTime()
        queue.async { [weak self] in
            // Avoid overlapping classifier runs.
            defer { self?.isProcessing = false }
            guard let self else { return }
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
            try? handler.perform([request])
            let elapsed = (CACurrentMediaTime() - start) * 1000
            if self.diagnosticsEnabled {
                DispatchQueue.main.async {
                    self.diagnostics.inferenceMs = elapsed
                    self.diagnostics.fps = self.tracker.updateFPS()
                }
            }
        }
    }

    private func handleResults(request: VNRequest) {
        // Convert classifier labels into clearer walk/do-not-walk language.
        let results = (request.results as? [VNClassificationObservation]) ?? []
        guard let best = results.first else {
            setStatus("Signal: Unknown")
            updateTopDetections([])
            return
        }
        let label = best.identifier.lowercased()
        let status: String
        if label.contains("walk") && !label.contains("dont") && !label.contains("don't") {
            // Plain walk label means safe/permissive signal.
            status = "Walk"
        } else if label.contains("dont") || label.contains("don't") || label.contains("no") {
            // Handle different spellings a future model might output.
            status = "Do Not Walk"
        } else {
            status = best.identifier.replacingOccurrences(of: "_", with: " ")
        }
        setStatus("Signal: \(status)")
        updateTopDetections(results.prefix(3).map { "\($0.identifier) \(Int($0.confidence * 100))%" })
    }

    private func updateTopDetections(_ detections: [String]) {
        // Diagnostics overlay is optional, so skip work when hidden.
        guard diagnosticsEnabled else { return }
        DispatchQueue.main.async {
            if self.diagnostics.topDetections != detections {
                self.diagnostics.topDetections = detections
            }
        }
    }

    private func setStatus(_ text: String) {
        // Main queue for SwiftUI state.
        DispatchQueue.main.async {
            if self.statusText != text {
                self.statusText = text
            }
        }
    }

    private func shouldProcess() -> Bool {
        // Throttle crosswalk inference for performance.
        guard !isProcessing else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastProcess) > 0.55 else { return false }
        lastProcess = now
        return true
    }
}

// Experimental heuristic: compare brightness on the left and right side of
// the frame to suggest a simple direction. This is not full navigation.
final class PathGuidanceViewModel: ObservableObject {
    // Experimental guidance text; this is deliberately not a navigation system.
    @Published var statusText: String = "Guidance: —"
    @Published var diagnostics = DiagnosticsInfo()
    var diagnosticsEnabled = false

    private let queue = DispatchQueue(label: "echosight.path.guidance", qos: .userInitiated)
    private var isProcessing = false
    private var lastProcess = Date.distantPast
    private let tracker = DiagnosticsTracker()

    func process(sampleBuffer: CMSampleBuffer) {
        // Sample frames instead of processing every camera buffer.
        guard shouldProcess() else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true
        let start = CACurrentMediaTime()
        queue.async { [weak self] in
            // Always clear the busy flag after this frame finishes.
            defer { self?.isProcessing = false }
            guard let self else { return }
            // Compare average brightness in left and right regions.
            let left = self.averageLuma(in: buffer, region: CGRect(x: 0.0, y: 0.3, width: 0.45, height: 0.4))
            let right = self.averageLuma(in: buffer, region: CGRect(x: 0.55, y: 0.3, width: 0.45, height: 0.4))
            let status: String
            if abs(left - right) < 10 {
                // Similar brightness means no strong left/right preference.
                status = "Guidance: Ahead"
            } else if left < right {
                // Right side appears brighter/clearer by this heuristic.
                status = "Guidance: Move right"
            } else {
                // Left side appears brighter/clearer by this heuristic.
                status = "Guidance: Move left"
            }
            self.setStatus(status)
            let elapsed = (CACurrentMediaTime() - start) * 1000
            if self.diagnosticsEnabled {
                DispatchQueue.main.async {
                    self.diagnostics.inferenceMs = elapsed
                    self.diagnostics.fps = self.tracker.updateFPS()
                    self.diagnostics.computeUnits = "Heuristic"
                    self.diagnostics.usesNeuralEngine = false
                    self.diagnostics.modelName = "PathGuidance (Heuristic)"
                    if self.diagnostics.topDetections != [status] {
                        self.diagnostics.topDetections = [status]
                    }
                }
            }
        }
    }

    private func averageLuma(in buffer: CVPixelBuffer, region: CGRect) -> Double {
        // Lock pixel memory while reading raw BGRA camera bytes.
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
                // Pixel order is BGRA for the configured camera buffer format.
                let pixel = row.advanced(by: x * 4)
                let b = Double(pixel[0])
                let g = Double(pixel[1])
                let r = Double(pixel[2])
                // Standard luma formula weights green most heavily.
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                sum += luma
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return sum / count
    }

    private func setStatus(_ text: String) {
        // Main queue for SwiftUI state updates.
        DispatchQueue.main.async {
            if self.statusText != text {
                self.statusText = text
            }
        }
    }

    private func shouldProcess() -> Bool {
        // The heuristic is cheap, but throttling still helps battery and UI smoothness.
        guard !isProcessing else { return false }
        let now = Date()
        guard now.timeIntervalSince(lastProcess) > 0.7 else { return false }
        lastProcess = now
        return true
    }
}
