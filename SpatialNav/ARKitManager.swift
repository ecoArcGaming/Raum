import Foundation
import ARKit
import SceneKit

class ARKitManager: NSObject, ObservableObject {
    private var arSession: ARSession
    private var currentFrame: ARFrame?
    
    @Published var isARSupported = ARWorldTrackingConfiguration.isSupported
    @Published var isSessionRunning = false
    
    override init() {
        arSession = ARSession()
        super.init()
        arSession.delegate = self
    }
    
    func startSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("📱 ARKit not supported on this device")
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        
        arSession.run(configuration)
        isSessionRunning = true
        print("📱 ARKit session started")
    }
    
    func pauseSession() {
        arSession.pause()
        isSessionRunning = false
        print("📱 ARKit session paused")
    }
    
    func get3DPosition(for boundingBox: CGRect, in imageSize: CGSize) -> (distance: Float, azimuth: Float, elevation: Float)? {
        guard let frame = currentFrame else {
            print("📱 No current AR frame available")
            return nil
        }
        
        // Convert bounding box center to screen coordinates
        let centerX = boundingBox.midX * imageSize.width
        let centerY = boundingBox.midY * imageSize.height
        let screenPoint = CGPoint(x: centerX, y: centerY)
        
        print("📱 ARKit - Screen point: (\(centerX), \(centerY))")
        
        // Perform hit test to find 3D world position
        let hitTestResults = frame.hitTest(screenPoint, types: [.estimatedHorizontalPlane, .estimatedVerticalPlane, .existingPlane, .featurePoint])
        
        if let hitResult = hitTestResults.first {
            let worldTransform = hitResult.worldTransform
            let worldPosition = SIMD3<Float>(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
            
            // Calculate distance from camera
            let cameraPosition = frame.camera.transform.columns.3
            let cameraPos = SIMD3<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z)
            
            let distance = simd_distance(worldPosition, cameraPos)
            
            // Calculate azimuth (horizontal angle) relative to camera
            let deltaX = worldPosition.x - cameraPos.x
            let deltaZ = worldPosition.z - cameraPos.z
            let azimuth = atan2(deltaX, -deltaZ) * 180 / Float.pi
            
            // Calculate elevation (vertical angle)
            let deltaY = worldPosition.y - cameraPos.y
            let horizontalDistance = sqrt(deltaX * deltaX + deltaZ * deltaZ)
            let elevation = atan2(deltaY, horizontalDistance) * 180 / Float.pi
            
            print("📱 ARKit - 3D Position: (\(worldPosition.x), \(worldPosition.y), \(worldPosition.z))")
            print("📱 ARKit - Distance: \(distance)m, Azimuth: \(azimuth)°, Elevation: \(elevation)°")
            
            return (distance: distance, azimuth: azimuth, elevation: elevation)
        } else {
            // Fallback: estimate based on bounding box size and position
            print("📱 ARKit - No hit test result, using fallback estimation")
            return estimatePositionFromBoundingBox(boundingBox)
        }
    }
    
    private func estimatePositionFromBoundingBox(_ boundingBox: CGRect) -> (distance: Float, azimuth: Float, elevation: Float) {
        // Estimate distance based on bounding box size (larger box = closer object)
        let boxArea = boundingBox.width * boundingBox.height
        let estimatedDistance = Float(1.0 / sqrt(boxArea)) * 5.0 // Scale factor
        let clampedDistance = max(0.5, min(10.0, estimatedDistance))
        
        // Calculate azimuth from horizontal position
        let fieldOfView: Float = 60.0
        let azimuth = Float(boundingBox.midX - 0.5) * fieldOfView
        
        // Calculate elevation from vertical position
        let verticalFOV: Float = 45.0
        let elevation = Float(0.5 - boundingBox.midY) * verticalFOV
        
        print("📱 ARKit Fallback - Distance: \(clampedDistance)m, Azimuth: \(azimuth)°, Elevation: \(elevation)°")
        
        return (distance: clampedDistance, azimuth: azimuth, elevation: elevation)
    }
    
    func getCurrentCameraTransform() -> simd_float4x4? {
        return currentFrame?.camera.transform
    }
}

extension ARKitManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        currentFrame = frame
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("📱 ARKit session failed: \(error)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("📱 ARKit session was interrupted")
        isSessionRunning = false
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("📱 ARKit session interruption ended")
        isSessionRunning = true
    }
}