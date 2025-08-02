import Foundation
import Vision
import AVFoundation
import CoreML

class ObjectDetectionManager: ObservableObject {
    @Published var detectedObjects: [DetectedObject] = []
    
    private var visionModel: VNCoreMLModel?
    private let sequenceHandler = VNSequenceRequestHandler()
    private let targetMatcher = TargetMatcher()
    
    init() {
        setupObjectDetection()
    }
    
    private func setupObjectDetection() {
        guard let modelURL = Bundle.main.url(forResource: "yolov5s", withExtension: "mlmodelc") else {
            print("FATAL: YOLOv5 model not found")
            return
        }
        
        do {
            let model = try MLModel(contentsOf: modelURL)
            visionModel = try VNCoreMLModel(for: model)
            print("YOLOv5 model loaded")
        } catch {
            print("Failed to load YOLOv5 model: \(error)")
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
            print("No vision model available!")
            completion([])
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
        
        var allDetectedObjects: [DetectedObject] = []
        
        // First, collect all detected objects regardless of target matching
        for observation in results {
            if let objectObservation = observation as? VNRecognizedObjectObservation {
                let topLabel = objectObservation.labels.first
                if let label = topLabel, label.confidence > 0.15 { // Lower threshold to catch more objects for NLP matching
                    
                    let boundingBox = objectObservation.boundingBox
                    let azimuth = calculateAzimuth(from: boundingBox.midX)
                    let distance = estimateDistance(from: boundingBox)
                    
                    let detectedObject = DetectedObject(
                        label: label.identifier,
                        confidence: label.confidence,
                        boundingBox: boundingBox,
                        azimuth: azimuth,
                        distance: distance
                    )
                    
                    allDetectedObjects.append(detectedObject)
                    print("Detection - \(label.identifier) (conf: \(label.confidence))")
                }
            } else if let coreMLObservation = observation as? VNCoreMLFeatureValueObservation {
                processYOLOv5Output(coreMLObservation, targetObject: targetObject, detectedObjects: &allDetectedObjects)
            } else if let classificationObservation = observation as? VNClassificationObservation {
                if classificationObservation.confidence > 0.2 { // Lower threshold for NLP matching
                    
                    let detectedObject = DetectedObject(
                        label: classificationObservation.identifier,
                        confidence: classificationObservation.confidence,
                        boundingBox: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                        azimuth: 0,
                        distance: 1.0
                    )
                    
                    allDetectedObjects.append(detectedObject)
                    print("Classification - \(classificationObservation.identifier) (conf: \(classificationObservation.confidence))")
                }
            }
        }
        
        // Now use NLP-based matching to find relevant objects
        print("Target Matching - Found \(allDetectedObjects.count) raw detections, matching against target: '\(targetObject)'")
        let matchedObjects = targetMatcher.findRelevantObjects(targetString: targetObject, detectedObjects: allDetectedObjects)
        
        // Extract the DetectedObject from MatchedObject results
        let relevantDetectedObjects = matchedObjects.map { matchedObject in
            print("Target Match - \(matchedObject.object.label) (relevance: \(String(format: "%.3f", matchedObject.relevanceScore)))")
            return matchedObject.object
        }
        
        DispatchQueue.main.async {
            completion(relevantDetectedObjects)
        }
    }
    
    private func processYOLOv5Output(_ observation: VNCoreMLFeatureValueObservation, targetObject: String, detectedObjects: inout [DetectedObject]) {
        // this is a fallback
        guard let multiArray = observation.featureValue.multiArrayValue else {
            print("YOLOv5: No multi-array output found")
            return
        }
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
    let elevation: Float
    
    init(label: String, confidence: Float, boundingBox: CGRect, azimuth: Float, distance: Float, elevation: Float = 0) {
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.azimuth = azimuth
        self.distance = distance
        self.elevation = elevation
    }
}
