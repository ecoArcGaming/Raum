import Foundation
import Speech
import AVFoundation

class SpeechRecognitionManager: ObservableObject {
    @Published var recognizedText = ""
    @Published var isRecording = false
    @Published var isAuthorized = false
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        requestPermissions()
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self?.isAuthorized = true
                case .denied, .restricted, .notDetermined:
                    self?.isAuthorized = false
                @unknown default:
                    self?.isAuthorized = false
                }
            }
        }
    }
    
    func startRecording() {
        guard isAuthorized else {
            print("Speech recognition not authorized")
            return
        }
        
        if audioEngine.isRunning {
            stopRecording()
            return
        }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            
            let inputNode = audioEngine.inputNode
            guard let recognitionRequest = recognitionRequest else {
                print("Unable to create recognition request")
                return
            }
            
            recognitionRequest.shouldReportPartialResults = true
            
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                var isFinal = false
                
                if let result = result {
                    let transcribedText = result.bestTranscription.formattedString
                    print("🎤 Speech Recognition - Partial: \(transcribedText)")
                    
                    DispatchQueue.main.async {
                        self?.recognizedText = transcribedText
                    }
                    isFinal = result.isFinal
                    
                    if isFinal {
                        print("🎤 Speech Recognition - FINAL: \(transcribedText)")
                    }
                }
                
                if let error = error {
                    print("🎤 Speech Recognition Error: \(error)")
                }
                
                if error != nil || isFinal {
                    self?.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    
                    self?.recognitionRequest = nil
                    self?.recognitionTask = nil
                    
                    DispatchQueue.main.async {
                        self?.isRecording = false
                        print("🎤 Speech Recording Stopped")
                    }
                }
            }
            
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            recognizedText = ""
            print("🎤 Speech Recording Started")
            
        } catch {
            print("🎤 Failed to start recording: \(error)")
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRecording = false
    }
}