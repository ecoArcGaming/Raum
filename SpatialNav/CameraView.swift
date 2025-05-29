import SwiftUI
import AVFoundation
import Vision
import ARKit

struct CameraView: UIViewRepresentable {
    let objectDetectionManager: ObjectDetectionManager
    let spatialAudioManager: SpatialAudioManager
    let arkitManager: ARKitManager
    let targetObject: String
    let onObjectDetected: (DetectedObject) -> Void
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.delegate = context.coordinator
        view.arkitManager = arkitManager
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        context.coordinator.targetObject = targetObject
        context.coordinator.onObjectDetected = onObjectDetected
        context.coordinator.arkitManager = arkitManager
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CameraPreviewDelegate {
        let parent: CameraView
        var targetObject: String = ""
        var onObjectDetected: ((DetectedObject) -> Void)?
        var arkitManager: ARKitManager?
        
        init(_ parent: CameraView) {
            self.parent = parent
            self.targetObject = parent.targetObject
            self.onObjectDetected = parent.onObjectDetected
            self.arkitManager = parent.arkitManager
        }
        
        func didCaptureFrame(_ pixelBuffer: CVPixelBuffer, imageSize: CGSize) {
            parent.objectDetectionManager.detectObjects(in: pixelBuffer, targetObject: targetObject) { [weak self] objects in
                guard let self = self else { return }
                
                for object in objects {
                    // Use ARKit to get real 3D position if available
                    if let arkitManager = self.arkitManager,
                       arkitManager.isSessionRunning,
                       let position3D = arkitManager.get3DPosition(for: object.boundingBox, in: imageSize) {
                        
                        // Create new object with ARKit-derived position
                        let enhancedObject = DetectedObject(
                            label: object.label,
                            confidence: object.confidence,
                            boundingBox: object.boundingBox,
                            azimuth: position3D.azimuth,
                            distance: position3D.distance,
                            elevation: position3D.elevation
                        )
                        
                        self.onObjectDetected?(enhancedObject)
                    } else {
                        // Fallback to original object with estimated position
                        self.onObjectDetected?(object)
                    }
                    break
                }
            }
        }
    }
}

protocol CameraPreviewDelegate: AnyObject {
    func didCaptureFrame(_ pixelBuffer: CVPixelBuffer, imageSize: CGSize)
}

class CameraPreviewView: UIView {
    weak var delegate: CameraPreviewDelegate?
    var arkitManager: ARKitManager?
    
    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var videoOutput: AVCaptureVideoDataOutput?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        
        guard let captureSession = captureSession else { return }
        
        captureSession.sessionPreset = .medium
        
        guard let backCamera = AVCaptureDevice.default(for: .video) else {
            print("Unable to access back camera")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            
            if let videoOutput = videoOutput, captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer?.videoGravity = .resizeAspectFill
            videoPreviewLayer?.frame = bounds
            
            if let videoPreviewLayer = videoPreviewLayer {
                layer.addSublayer(videoPreviewLayer)
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
            
            // Start ARKit session if available
            arkitManager?.startSession()
            
        } catch {
            print("Camera setup error: \(error)")
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer?.frame = bounds
    }
    
    deinit {
        captureSession?.stopRunning()
        arkitManager?.pauseSession()
    }
}

extension CameraPreviewView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Get image size for ARKit calculations
        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        let imageSize = CGSize(width: imageWidth, height: imageHeight)
        
        delegate?.didCaptureFrame(pixelBuffer, imageSize: imageSize)
    }
}