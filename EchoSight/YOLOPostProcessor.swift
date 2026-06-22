import CoreML
import UIKit
import Vision

struct DetectedObject {
    let label: String
    let confidence: Double
    let rect: CGRect
}

struct YOLOPostProcessor {
    static let cocoLabels: [String] = [
        "person","bicycle","car","motorcycle","airplane","bus","train","truck","boat","traffic light",
        "fire hydrant","stop sign","parking meter","bench","bird","cat","dog","horse","sheep","cow",
        "elephant","bear","zebra","giraffe","backpack","umbrella","handbag","tie","suitcase","frisbee",
        "skis","snowboard","sports ball","kite","baseball bat","baseball glove","skateboard","surfboard","tennis racket","bottle",
        "wine glass","cup","fork","knife","spoon","bowl","banana","apple","sandwich","orange",
        "broccoli","carrot","hot dog","pizza","donut","cake","chair","couch","potted plant","bed",
        "dining table","toilet","tv","laptop","mouse","remote","keyboard","cell phone","microwave","oven",
        "toaster","sink","refrigerator","book","clock","vase","scissors","teddy bear","hair drier","toothbrush"
    ]

    static func decode(
        observation: VNCoreMLFeatureValueObservation,
        labels: [String] = cocoLabels,
        confidenceThreshold: Double = 0.25,
        iouThreshold: Double = 0.45
    ) -> [DetectedObject] {
        guard let array = observation.featureValue.multiArrayValue else { return [] }
        let accessor = MultiArrayAccessor(array)
        guard let layout = accessor.layout else { return [] }

        var detections: [DetectedObject] = []
        for predIndex in 0..<layout.numPredictions {
            let (bx, by, bw, bh) = layout.box(predIndex, accessor)
            let (bestClass, bestScore) = layout.bestClass(predIndex, accessor, labelsCount: labels.count)
            if bestScore < confidenceThreshold { continue }
            let label = bestClass < labels.count ? labels[bestClass] : "object"
            let rect = CGRect(
                x: max(0, bx - bw / 2),
                y: max(0, by - bh / 2),
                width: min(1, bw),
                height: min(1, bh)
            )
            detections.append(DetectedObject(label: label, confidence: bestScore, rect: rect))
        }

        return nonMaxSuppression(detections, iouThreshold: iouThreshold)
    }

    static func decodeNMS(
        confidenceObservation: VNCoreMLFeatureValueObservation,
        coordinatesObservation: VNCoreMLFeatureValueObservation,
        labels: [String] = cocoLabels,
        confidenceThreshold: Double = 0.35
    ) -> [DetectedObject] {
        guard let confidenceArray = confidenceObservation.featureValue.multiArrayValue,
              let coordinateArray = coordinatesObservation.featureValue.multiArrayValue,
              let confidenceMatrix = MultiArrayMatrix(confidenceArray, preferredColumnCount: labels.count),
              let coordinateMatrix = MultiArrayMatrix(coordinateArray, preferredColumnCount: 4) else {
            return []
        }

        let detectionCount = min(confidenceMatrix.rows, coordinateMatrix.rows)
        let classCount = min(confidenceMatrix.columns, labels.count)
        var detections: [DetectedObject] = []

        for row in 0..<detectionCount {
            var bestClass = 0
            var bestConfidence = 0.0
            for classIndex in 0..<classCount {
                let confidence = confidenceMatrix.value(row: row, column: classIndex)
                if confidence > bestConfidence {
                    bestConfidence = confidence
                    bestClass = classIndex
                }
            }

            guard bestConfidence >= confidenceThreshold else { continue }
            let coordinates = (0..<4).map { coordinateMatrix.value(row: row, column: $0) }
            let label = bestClass < labels.count ? labels[bestClass] : "object"
            detections.append(
                DetectedObject(
                    label: label,
                    confidence: bestConfidence,
                    rect: normalizedBoundingBox(from: coordinates)
                )
            )
        }

        return detections.sorted { $0.confidence > $1.confidence }
    }

    private static func nonMaxSuppression(_ detections: [DetectedObject], iouThreshold: Double) -> [DetectedObject] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var selected: [DetectedObject] = []
        var used = Array(repeating: false, count: sorted.count)

        for i in 0..<sorted.count {
            if used[i] { continue }
            let det = sorted[i]
            selected.append(det)
            for j in (i + 1)..<sorted.count {
                if used[j] { continue }
                if iou(det.rect, sorted[j].rect) > iouThreshold {
                    used[j] = true
                }
            }
        }
        return selected
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        if inter.isNull { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        return unionArea > 0 ? Double(interArea / unionArea) : 0
    }

    private static func normalizedBoundingBox(from coordinates: [Double]) -> CGRect {
        guard coordinates.count == 4 else { return .zero }
        var values = coordinates
        let maxValue = values.map { abs($0) }.max() ?? 1
        if maxValue > 2 {
            let scale = max(640, maxValue)
            values = values.map { $0 / scale }
        }

        let centerX = values[0]
        let centerY = values[1]
        let width = abs(values[2])
        let height = abs(values[3])
        return clamp(
            CGRect(
                x: centerX - width / 2,
                y: centerY - height / 2,
                width: width,
                height: height
            )
        )
    }

    private static func clamp(_ rect: CGRect) -> CGRect {
        let minX = min(max(rect.minX, 0), 1)
        let minY = min(max(rect.minY, 0), 1)
        let maxX = min(max(rect.maxX, 0), 1)
        let maxY = min(max(rect.maxY, 0), 1)
        guard maxX > minX, maxY > minY else {
            return CGRect(
                x: min(max(rect.midX, 0), 1),
                y: min(max(rect.midY, 0), 1),
                width: 0.01,
                height: 0.01
            )
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private struct MultiArrayAccessor {
    let array: MLMultiArray
    let shape: [Int]
    let stride: [Int]

    init(_ array: MLMultiArray) {
        self.array = array
        self.shape = array.shape.map { $0.intValue }
        self.stride = array.strides.map { $0.intValue }
    }

    var layout: YOLOLayout? {
        guard shape.count >= 2 else { return nil }
        if shape.count == 3 {
            let s0 = shape[0], s1 = shape[1], s2 = shape[2]
            if s1 == 84 || s1 == 85 {
                return YOLOLayout(numPredictions: s2, featureCount: s1, featuresFirst: true)
            } else if s2 == 84 || s2 == 85 {
                return YOLOLayout(numPredictions: s1, featureCount: s2, featuresFirst: false)
            }
        }
        if shape.count == 2 {
            let s0 = shape[0], s1 = shape[1]
            if s1 > s0 {
                return YOLOLayout(numPredictions: s0, featureCount: s1, featuresFirst: false)
            } else {
                return YOLOLayout(numPredictions: s1, featureCount: s0, featuresFirst: true)
            }
        }
        return nil
    }

    func value(_ featureIndex: Int, _ predIndex: Int, layout: YOLOLayout) -> Double {
        let f = layout.featuresFirst
        let idx: Int
        if shape.count == 3 {
            if f {
                idx = featureIndex * stride[1] + predIndex * stride[2]
            } else {
                idx = predIndex * stride[1] + featureIndex * stride[2]
            }
        } else {
            if f {
                idx = featureIndex * stride[0] + predIndex * stride[1]
            } else {
                idx = predIndex * stride[0] + featureIndex * stride[1]
            }
        }
        return array[idx].doubleValue
    }
}

private struct MultiArrayMatrix {
    let array: MLMultiArray
    let rows: Int
    let columns: Int
    private let rowStride: Int
    private let columnStride: Int
    private let baseOffset: Int

    init?(_ array: MLMultiArray, preferredColumnCount: Int) {
        let shape = array.shape.map { $0.intValue }
        let strides = array.strides.map { $0.intValue }
        guard shape.count >= 2, shape.count <= 3 else { return nil }

        if shape.count == 2 {
            if shape[1] == preferredColumnCount {
                self.rows = shape[0]
                self.columns = shape[1]
                self.rowStride = strides[0]
                self.columnStride = strides[1]
                self.baseOffset = 0
            } else if shape[0] == preferredColumnCount {
                self.rows = shape[1]
                self.columns = shape[0]
                self.rowStride = strides[1]
                self.columnStride = strides[0]
                self.baseOffset = 0
            } else {
                return nil
            }
        } else if shape[2] == preferredColumnCount {
            self.rows = shape[1]
            self.columns = shape[2]
            self.rowStride = strides[1]
            self.columnStride = strides[2]
            self.baseOffset = 0
        } else if shape[1] == preferredColumnCount {
            self.rows = shape[2]
            self.columns = shape[1]
            self.rowStride = strides[2]
            self.columnStride = strides[1]
            self.baseOffset = 0
        } else if shape[0] == preferredColumnCount {
            self.rows = shape[1]
            self.columns = shape[0]
            self.rowStride = strides[1]
            self.columnStride = strides[0]
            self.baseOffset = 0
        } else {
            return nil
        }

        guard rows > 0, columns > 0 else { return nil }
        self.array = array
    }

    func value(row: Int, column: Int) -> Double {
        let index = baseOffset + row * rowStride + column * columnStride
        return array[index].doubleValue
    }
}

private struct YOLOLayout {
    let numPredictions: Int
    let featureCount: Int
    let featuresFirst: Bool

    func box(_ predIndex: Int, _ accessor: MultiArrayAccessor) -> (Double, Double, Double, Double) {
        let bx = accessor.value(0, predIndex, layout: self)
        let by = accessor.value(1, predIndex, layout: self)
        let bw = accessor.value(2, predIndex, layout: self)
        let bh = accessor.value(3, predIndex, layout: self)
        return (bx, by, bw, bh)
    }

    func bestClass(_ predIndex: Int, _ accessor: MultiArrayAccessor, labelsCount: Int) -> (Int, Double) {
        let hasObjectness = featureCount == labelsCount + 5
        let classStart = hasObjectness ? 5 : 4
        let classCount = max(0, featureCount - classStart)
        let objectness = hasObjectness ? accessor.value(4, predIndex, layout: self) : 1.0
        var bestIndex = 0
        var bestScore = 0.0
        for i in 0..<classCount {
            let score = objectness * accessor.value(classStart + i, predIndex, layout: self)
            if score > bestScore {
                bestScore = score
                bestIndex = i
            }
        }
        if bestIndex >= labelsCount {
            return (labelsCount - 1, bestScore)
        }
        return (bestIndex, bestScore)
    }
}

#if DEBUG
enum YOLOPostProcessorDebug {
    static func runSelfTestIfAvailable() {
        guard let url = Bundle.main.url(forResource: "yolo_test", withExtension: "jpg") else {
            print("YOLO self-test skipped: add yolo_test.jpg to bundle to run.")
            return
        }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            print("YOLO self-test image failed to load.")
            return
        }
        guard let cgImage = image.cgImage else { return }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        if let modelInfo = VisionCoreMLPipeline.loadModel(named: "yolov8n") {
            let request = VNCoreMLRequest(model: modelInfo.vnModel) { request, _ in
                if let obs = request.results?.compactMap({ $0 as? VNCoreMLFeatureValueObservation }).first {
                    let detections = YOLOPostProcessor.decode(observation: obs)
                    print("YOLO self-test detections: \(detections.prefix(5))")
                }
            }
            try? handler.perform([request])
        }
    }
}
#endif
