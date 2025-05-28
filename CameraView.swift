import SwiftUI
import AVFoundation
import Vision

struct CameraView: UIViewRepresentable {
    let objectDetectionManager: ObjectDetectionManager
    let spatialAudioManager: SpatialAudioManager
    let targetObject: String
    let onObjectDetected: (DetectedObject) -> Void
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.delegate = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        context.coordinator.targetObject = targetObject
        context.coordinator.onObjectDetected = onObjectDetected
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CameraPreviewDelegate {
        let parent: CameraView
        var targetObject: String = ""
        var onObjectDetected: ((DetectedObject) -> Void)?
        
        init(_ parent: CameraView) {
            self.parent = parent
            self.targetObject = parent.targetObject
            self.onObjectDetected = parent.onObjectDetected
        }
        
        func didCaptureFrame(_ pixelBuffer: CVPixelBuffer) {
            parent.objectDetectionManager.detectObjects(in: pixelBuffer, targetObject: targetObject) { [weak self] objects in
                guard let self = self else { return }
                
                for object in objects {
                    self.onObjectDetected?(object)
                    break
                }
            }
        }
    }
}

protocol CameraPreviewDelegate: AnyObject {
    func didCaptureFrame(_ pixelBuffer: CVPixelBuffer)
}

class CameraPreviewView: UIView {
    weak var delegate: CameraPreviewDelegate?
    
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
    }
}

extension CameraPreviewView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        delegate?.didCaptureFrame(pixelBuffer)
    }
}