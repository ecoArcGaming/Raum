
import Foundation
import NaturalLanguage

struct MatchedObject: Identifiable {
    let id = UUID()
    let object: DetectedObject
    let relevanceScore: Double // Higher is more relevant (e.g., 0.0 to 1.0)

    init(detectedObject: DetectedObject, relevance: Double) {
        self.object = detectedObject
        self.relevanceScore = relevance
    }
}

class TargetMatcher {

    private let sentenceEmbedding: NLEmbedding?

    // Relevance threshold: Tune this for min matched score
    private let relevanceThreshold: Double = 0.25

    init() {
        if let embedding = NLEmbedding.sentenceEmbedding(for: .english) {
            self.sentenceEmbedding = embedding
            print("NLEmbedding for English initialized.")
        } else {
            self.sentenceEmbedding = nil
            print("Failed to initialize NLEmbedding for English.!")
        }
    }
    func findRelevantObjects(targetString: String, detectedObjects: [DetectedObject]) -> [MatchedObject] {
        guard let embeddingModel = self.sentenceEmbedding else {
            print("Sentence embedding model not available!")
            return []
        }

        let trimmedTargetString = targetString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTargetString.isEmpty else {
            return []
        }

        var matchedObjects: [MatchedObject] = []

        for detectedObject in detectedObjects {
            // Use NLEmbedding's direct distance computation between strings
            let distance = embeddingModel.distance(between: trimmedTargetString.lowercased(),
                                                 and: detectedObject.label.lowercased(),
                                                 distanceType: .cosine)
            
            // Convert distance to similarity score (higher is better)
            // Cosine similarity = 1 - cosine_distance
            // from -1 to 1, where 1 = identical, 0 = orthogonal, -1 = opposite
            // scaled by YOLO confidence
           
            let finalRelevance = (1.0 - distance) * Double(detectedObject.confidence)

            print("Matching '\(trimmedTargetString)' with '\(detectedObject.label)': Dist=\(String(format: "%.2f", distance)), Rel=\(String(format: "%.2f", finalRelevance))")

            if finalRelevance >= self.relevanceThreshold {
                matchedObjects.append(MatchedObject(detectedObject: detectedObject, relevance: finalRelevance))
            }
        }

        // Sort by relevance score, highest first
        return matchedObjects.sorted { $0.relevanceScore > $1.relevanceScore }
    }
}
