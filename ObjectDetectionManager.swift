import Foundation
import Vision
import AVFoundation
import CoreML

class ObjectDetectionManager: ObservableObject {
    @Published var detectedObjects: [DetectedObject] = []
    
    private var visionModel: VNCoreMLModel?
    private let sequenceHandler = VNSequenceRequestHandler()
    
    init() {
        setupObjectDetection()
    }
    
    private func setupObjectDetection() {
        guard let modelURL = Bundle.main.url(forResource: "YOLOv3", withExtension: "mlmodelc") else {
            setupClassificationModel()
            return
        }
        
        do {
            let model = try MobileNetV2FP16(contentsOf: modelURL)
            visionModel = try VNCoreMLModel(for: model.model)
        } catch {
            print("Failed to load YOLO model: \(error)")
            setupClassificationModel()
        }
    }
    
    private func setupClassificationModel() {
        guard let modelURL = Bundle.main.url(forResource: "MobileNetV2", withExtension: "mlmodelc") else {
            print("MobileNetV2 model not found - using built-in classification")
            return
        }
        
        do {
            let model = try MLModel(contentsOf: modelURL)
            visionModel = try VNCoreMLModel(for: model)
        } catch {
            print("Failed to load MobileNetV2 model: \(error)")
        }
    }
    
    func detectObjects(in pixelBuffer: CVPixelBuffer, targetObject: String, completion: @escaping ([DetectedObject]) -> Void) {
        if let model = visionModel {
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                if let error = error {
                    print("Object detection error: \(error)")
                    completion([])
                    return
                }
                
                self?.processDetectionResults(request.results, targetObject: targetObject, completion: completion)
            }
            
            request.imageCropAndScaleOption = .scaleFill
            
            do {
                try sequenceHandler.perform([request], on: pixelBuffer)
            } catch {
                print("Failed to perform detection: \(error)")
                completion([])
            }
        } else {
            useBuiltInClassification(pixelBuffer: pixelBuffer, targetObject: targetObject, completion: completion)
        }
    }
    
    private func useBuiltInClassification(pixelBuffer: CVPixelBuffer, targetObject: String, completion: @escaping ([DetectedObject]) -> Void) {
        let request = VNClassifyImageRequest { [weak self] request, error in
            if let error = error {
                print("Classification error: \(error)")
                completion([])
                return
            }
            
            self?.processDetectionResults(request.results, targetObject: targetObject, completion: completion)
        }
        
        do {
            try sequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            print("Failed to perform classification: \(error)")
            completion([])
        }
    }
    
    private func processDetectionResults(_ results: [VNObservation]?, targetObject: String, completion: @escaping ([DetectedObject]) -> Void) {
        guard let results = results else {
            completion([])
            return
        }
        
        var detectedObjects: [DetectedObject] = []
        
        for observation in results {
            if let objectObservation = observation as? VNRecognizedObjectObservation {
                let topLabel = objectObservation.labels.first
                if let label = topLabel,
                   label.confidence > 0.3,
                   isMatchingTarget(label.identifier, target: targetObject) {
                    
                    let boundingBox = objectObservation.boundingBox
                    let centerX = boundingBox.midX
                    let centerY = boundingBox.midY
                    
                    let azimuth = calculateAzimuth(from: centerX)
                    let distance = estimateDistance(from: boundingBox)
                    
                    let detectedObject = DetectedObject(
                        label: label.identifier,
                        confidence: label.confidence,
                        boundingBox: boundingBox,
                        azimuth: azimuth,
                        distance: distance
                    )
                    
                    detectedObjects.append(detectedObject)
                }
            } else if let classificationObservation = observation as? VNClassificationObservation {
                if classificationObservation.confidence > 0.3,
                   isMatchingTarget(classificationObservation.identifier, target: targetObject) {
                    
                    let detectedObject = DetectedObject(
                        label: classificationObservation.identifier,
                        confidence: classificationObservation.confidence,
                        boundingBox: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                        azimuth: 0,
                        distance: 1.0
                    )
                    
                    detectedObjects.append(detectedObject)
                }
            }
        }
        
        DispatchQueue.main.async {
            completion(detectedObjects)
        }
    }
    
    private func isMatchingTarget(_ detected: String, target: String) -> Bool {
        let detectedLower = detected.lowercased()
        let targetWords = target.lowercased().components(separatedBy: " ")
        
        for word in targetWords {
            if detectedLower.contains(word) {
                return true
            }
        }
        
        let synonyms = getSynonyms(for: target.lowercased())
        for synonym in synonyms {
            if detectedLower.contains(synonym) {
                return true
            }
        }
        
        return false
    }
    
    private func getSynonyms(for object: String) -> [String] {
        let synonymMap: [String: [String]] = [
            "car": ["vehicle", "automobile", "sedan", "suv", "truck"],
            "honda": ["honda", "civic", "accord", "crv"],
            "black": ["dark", "black"],
            "suv": ["suv", "sport utility", "crossover"]
        ]
        
        var synonyms: [String] = []
        let words = object.components(separatedBy: " ")
        
        for word in words {
            if let wordSynonyms = synonymMap[word] {
                synonyms.append(contentsOf: wordSynonyms)
            }
        }
        
        return synonyms
    }
    
    private func calculateAzimuth(from normalizedX: CGFloat) -> Float {
        let fieldOfView: Float = 60.0
        let azimuth = Float(normalizedX - 0.5) * fieldOfView
        return azimuth
    }
    
    private func estimateDistance(from boundingBox: CGRect) -> Float {
        let objectHeight = boundingBox.height
        let estimatedDistance = 1.0 / Float(objectHeight)
        return max(0.5, min(10.0, estimatedDistance))
    }
}

struct DetectedObject: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect
    let azimuth: Float
    let distance: Float
}
