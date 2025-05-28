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
        
        audioEngine.connect(audioPlayerNode, to: audioEnvironment, format: nil)
        audioEngine.connect(audioEnvironment, to: audioEngine.mainMixerNode, format: nil)
        
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
        let x = sin(radians) * distance
        let z = -cos(radians) * distance
        
        audioPlayerNode.position = AVAudio3DPoint(x: x, y: 0, z: z)
        
        audioPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops) { [weak self] in
            DispatchQueue.main.async {
                self?.isPlaying = false
            }
        }
        
        audioPlayerNode.play()
        isPlaying = true
    }
    
    func playConfirmationSound() {
        guard let buffer = audioBuffer else { return }
        
        audioPlayerNode.position = AVAudio3DPoint(x: 0, y: 0, z: -1)
        
        audioPlayerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                self?.isPlaying = false
            }
        }
        
        audioPlayerNode.play()
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