import Foundation
import AVFoundation
import CoreAudio
import CoreMotion //  CoreMotion for head tracking

class SpatialAudioManager: ObservableObject {
    private var audioEngine: AVAudioEngine
    private var audioPlayerNode: AVAudioPlayerNode
    private var audioEnvironment: AVAudioEnvironmentNode
    private var audioBuffer: AVAudioPCMBuffer?

    // Head Tracking
    private var headphoneMotionManager: CMHeadphoneMotionManager?
    private let motionUpdateQueue = OperationQueue() 

    @Published var isPlaying = false
    @Published var headTrackingAvailable: Bool = false 

    // Store the format used for the player node
    private var playerNodeFormat: AVAudioFormat?
    private var isEngineSetup = false

    init() {
        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()
        audioEnvironment = AVAudioEnvironmentNode()
        headphoneMotionManager = CMHeadphoneMotionManager()
        
        // Check if head tracking is available 
        headTrackingAvailable = headphoneMotionManager?.isDeviceMotionAvailable ?? false
        if !headTrackingAvailable {
            print("Head tracking not available")
        }
        
        motionUpdateQueue.maxConcurrentOperationCount = 1
        motionUpdateQueue.qualityOfService = .userInteractive

        setupAudioSession()
        generateBeepTone()
        setupAudioEngine()
        startHeadTracking()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            //  try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP])
            try audioSession.setActive(true)
            print("Audio session configured")
        } catch {
            print("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    private func setupAudioEngine() {
        audioEngine.attach(audioPlayerNode)
        audioEngine.attach(audioEnvironment)

        audioEnvironment.renderingAlgorithm = .HRTFHQ

        // Set up listener position and orientation
        audioEnvironment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        audioEnvironment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: 0, y: 0, z: -1), // Looking along -Z axis
            up: AVAudio3DVector(x: 0, y: 1, z: 0)        // Y is up
        )

        connectAudioNodes()
    }

    private func generateBeepTone() {
        let sampleRate: Double = 44100
        let frequency: Double = 660 // A bit higher pitch for better localization, tune? 
        let duration: Double = 0.25 // also tune this 
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        //  mono format 
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("Error: Could not create audio format or buffer for beep tone.")
            return
        }
        self.playerNodeFormat = format 

        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData![0]
        let attackReleaseFrames = AVAudioFrameCount(sampleRate * 0.01) // 10ms attack/release, tune? 

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let amplitudeValue = sin(2.0 * Double.pi * frequency * time) * 0.4 //  lower amplitude, tune? 

            var envelope: Float = 1.0
            if frame < attackReleaseFrames { // Attack
                envelope = Float(frame) / Float(attackReleaseFrames)
            } else if frame > (Int(frameCount) - Int(attackReleaseFrames)) { // Release
                envelope = Float(Int(frameCount) - frame) / Float(attackReleaseFrames)
            }
            
            channelData[frame] = Float(amplitudeValue) * envelope
        }
        audioBuffer = buffer
    }
    
    private func connectAudioNodes() {
        guard let playerFormat = self.playerNodeFormat else {
            print("Error: Player node format not set. Cannot connect audio nodes.")
            return
        }
        
        audioEngine.connect(audioPlayerNode, to: audioEnvironment, format: playerFormat)
        
        // Connect environment node (now stereo, spatialized) to main mixer
        // Using nil format here lets the engine determine the appropriate stereo format.
        audioEngine.connect(audioEnvironment, to: audioEngine.mainMixerNode, format: nil) 
        audioEngine.prepare()
        isEngineSetup = true
        print("Audio engine prepared")
    }

    private func startAudioEngineIfNeeded() {
        guard isEngineSetup else {
            print("Audio engine not set up yet")
            return
        }
        
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                print("Audio engine started")
            } catch {
                print("Failed to start audio engine: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Head Tracking
    func startHeadTracking() {
        guard let manager = headphoneMotionManager, manager.isDeviceMotionAvailable else {
            print("Headphone motion manager not available")
            self.headTrackingAvailable = false
            return
        }

        guard !manager.isDeviceMotionActive else {
            print("Headphone motion updates are already active.")
            return
        }
        
        print("Attempting to start head tracking...")
        manager.startDeviceMotionUpdates(to: motionUpdateQueue) { [weak self] (motion, error) in
            guard let self = self, let motion = motion, error == nil else {
                if let error = error {
                    print("Headphone motion update error: \(error.localizedDescription)")
                    // Handle different types of errors
                    if (error as NSError).code == CMErrorDeviceRequiresMovement.rawValue ||
                       (error as NSError).code == CMErrorTrueNorthNotAvailable.rawValue {
                        // These are common errors that might resolve.
                        print("Transient head tracking error, continuing...")
                    } else {
                        // More critical error, might stop head tracking.
                        self?.stopHeadTracking(clearAvailability: true)
                    }
                }
                return
            }

            // Update listener orientation based on head motion
            let attitude = motion.attitude
            let rotationMatrix = attitude.rotationMatrix

            // Forward vector (assuming -Z local is forward)
            let forwardX = Float(-rotationMatrix.m31)
            let forwardY = Float(-rotationMatrix.m32)
            let forwardZ = Float(-rotationMatrix.m33)
            
            // Up vector (assuming +Y local is up)
            let upX = Float(rotationMatrix.m21)
            let upY = Float(rotationMatrix.m22)
            let upZ = Float(rotationMatrix.m23)

            DispatchQueue.main.async {
                self.audioEnvironment.listenerVectorOrientation = AVAudio3DVectorOrientation(
                    forward: AVAudio3DVector(x: forwardX, y: forwardY, z: forwardZ),
                    up: AVAudio3DVector(x: upX, y: upY, z: upZ)
                )
                if !self.headTrackingAvailable {
                    self.headTrackingAvailable = true
                    print("Head tracking now active")
                }
            }
        }
    }

    func stopHeadTracking(clearAvailability: Bool = false) {
        if let manager = headphoneMotionManager, manager.isDeviceMotionActive {
            print("Stopping head tracking updates.")
            manager.stopDeviceMotionUpdates()
        }
        if clearAvailability {
            self.headTrackingAvailable = false
        }
    }

    // MARK: - Sound Playbook Control
    func playDirectionalSound(azimuth: Float, elevation: Float = 0, distance: Float) {
        guard let buffer = audioBuffer else {
            print("Error: Audio buffer not available for playback.")
            return
        }

        // Ensure audio engine is started
        startAudioEngineIfNeeded()
        
        guard audioEngine.isRunning else {
            print("Audio engine failed to start")
            return
        }   
        
        let azimuthRadians = azimuth * .pi / 180.0
        let elevationRadians = elevation * .pi / 180.0
        let clampedDistance = max(0.3, min(10.0, distance))

        // Calculate 3D position
        let x = clampedDistance * sin(azimuthRadians) * cos(elevationRadians)
        let y = clampedDistance * sin(elevationRadians)
        let z = -clampedDistance * cos(azimuthRadians) * cos(elevationRadians)

        // Stop any currently playing sound first
        if audioPlayerNode.isPlaying {
            audioPlayerNode.stop()
        }

        // Set position and volume
        audioPlayerNode.position = AVAudio3DPoint(x: x, y: y, z: z)
        
        let maxVolumeDistance: Float = 10.0
        let normalizedDistance = min(1.0, clampedDistance / maxVolumeDistance)
        audioPlayerNode.volume = 1.0 - (normalizedDistance * 0.7)

        // Schedule and play the buffer
        audioPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops) { [weak self] in
            DispatchQueue.main.async {
                // Buffer finished playing (shouldn't happen with loops unless stopped)
            }
        }
        
        audioPlayerNode.play()
        
        DispatchQueue.main.async {
            self.isPlaying = true
        }
        
        print("Sound at Az: \(azimuth)°, El: \(elevation)°, Dist: \(clampedDistance)m")
    }

    func playConfirmationSound() {
        guard let buffer = audioBuffer else {
            print("Error: Audio buffer not available")
            return
        }

        startAudioEngineIfNeeded()
        
        guard audioEngine.isRunning else {
            print("Audio engine failed to start")
            return
        }
        
        // Stop any ongoing directional sound first
        if audioPlayerNode.isPlaying {
            audioPlayerNode.stop()
        }

        audioPlayerNode.position = AVAudio3DPoint(x: 0, y: 0, z: -0.5) // Close in front, tune? 
        audioPlayerNode.volume = 0.8

        audioPlayerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                self?.isPlaying = false
            }
        }
        
        audioPlayerNode.play()
        
        DispatchQueue.main.async {
            self.isPlaying = true
        }
        
        print("Playing confirmation sound")
    }

    func stopSound() {
        if audioPlayerNode.isPlaying {
            audioPlayerNode.stop()
        }
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
    
    deinit {
        stopHeadTracking()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        print("SpatialAudioManager deinitialized.")
    }
}
