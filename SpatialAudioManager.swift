import Foundation
import AVFoundation
import CoreAudio

class SpatialAudioManager: ObservableObject {
    private var audioEngine: AVAudioEngine
    private var audioPlayerNode: AVAudioPlayerNode
    private var audioEnvironment: AVAudioEnvironmentNode
    private var audioBuffer: AVAudioPCMBuffer?
    
    @Published var isPlaying = false
    
    init() {
        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()
        audioEnvironment = AVAudioEnvironmentNode()
        
        setupAudioEngine()
        generateBeepTone()
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(audioPlayerNode)
        audioEngine.attach(audioEnvironment)
        
        // Use explicit format to ensure channel compatibility
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        
        audioEngine.connect(audioPlayerNode, to: audioEnvironment, format: format)
        audioEngine.connect(audioEnvironment, to: audioEngine.mainMixerNode, format: format)
        
        audioEnvironment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        audioEnvironment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: 0, y: 0, z: -1),
            up: AVAudio3DVector(x: 0, y: 1, z: 0)
        )
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            
            try audioEngine.start()
        } catch {
            print("Audio engine setup failed: \(error)")
        }
    }
    
    private func generateBeepTone() {
        let sampleRate: Double = 44100
        let frequency: Double = 800
        let duration: Double = 0.5
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        
        buffer.frameLength = frameCount
        
        let channelData = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let amplitude = sin(2.0 * Double.pi * frequency * time) * 0.3
            let envelope = max(0, 1 - (time / duration))
            channelData[frame] = Float(amplitude * envelope)
        }
        
        audioBuffer = buffer
    }
    
    func playDirectionalSound(azimuth: Float, distance: Float) {
        guard let buffer = audioBuffer else { return }
        
        stopSound()
        
        let radians = azimuth * Float.pi / 180.0
        let clampedDistance = max(0.5, min(5.0, distance)) // Clamp distance for better audio positioning
        let x = sin(radians) * clampedDistance
        let z = -cos(radians) * clampedDistance
        
        audioPlayerNode.position = AVAudio3DPoint(x: x, y: 0, z: z)
        
        // Ensure audio engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("🔊 Failed to start audio engine: \(error)")
                return
            }
        }
        
        audioPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops) { [weak self] in
            DispatchQueue.main.async {
                self?.isPlaying = false
            }
        }
        
        if !audioPlayerNode.isPlaying {
            audioPlayerNode.play()
        }
        isPlaying = true
        
        print("🔊 Playing directional sound at azimuth: \(azimuth)°, distance: \(clampedDistance)m, position: (\(x), 0, \(z))")
    }
    
    func playConfirmationSound() {
        guard let buffer = audioBuffer else { return }
        
        stopSound()
        
        audioPlayerNode.position = AVAudio3DPoint(x: 0, y: 0, z: -1)
        
        // Ensure audio engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("🔊 Failed to start audio engine: \(error)")
                return
            }
        }
        
        audioPlayerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                self?.isPlaying = false
            }
        }
        
        if !audioPlayerNode.isPlaying {
            audioPlayerNode.play()
        }
        isPlaying = true
    }
    
    func stopSound() {
        audioPlayerNode.stop()
        isPlaying = false
    }
    
    func updateListenerOrientation(heading: Float) {
        let radians = heading * Float.pi / 180.0
        let forward = AVAudio3DVector(
            x: sin(radians),
            y: 0,
            z: -cos(radians)
        )
        
        audioEnvironment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: forward,
            up: AVAudio3DVector(x: 0, y: 1, z: 0)
        )
    }
    
    deinit {
        audioEngine.stop()
    }
}