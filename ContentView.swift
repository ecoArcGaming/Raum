import SwiftUI

struct ContentView: View {
    @StateObject private var objectDetectionManager = ObjectDetectionManager()
    @StateObject private var spatialAudioManager = SpatialAudioManager()
    @StateObject private var speechRecognitionManager = SpeechRecognitionManager()
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showCamera = false
    @State private var statusMessage = "Hold to speak what you're looking for"
    @State private var recordingTimer: Timer?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("SpatialNav")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityLabel("SpatialNav app")
                
                VStack(spacing: 20) {
                    if !speechRecognitionManager.recognizedText.isEmpty {
                        Text("You said: \"\(speechRecognitionManager.recognizedText)\"")
                            .font(.title3)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .accessibilityLabel("Recognized text: \(speechRecognitionManager.recognizedText)")
                    }
                    
                    Button(action: {}) {
                        VStack(spacing: 10) {
                            Image(systemName: speechRecognitionManager.isRecording ? "mic.fill" : isSearching ? "stop.circle.fill" : "mic")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                            
                            Text(speechRecognitionManager.isRecording ? "Recording..." : isSearching ? "Stop Search" : "Hold to Speak")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .background(speechRecognitionManager.isRecording ? Color.red : isSearching ? Color.orange : Color.blue)
                        .cornerRadius(20)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !speechRecognitionManager.isRecording && !isSearching {
                                    startRecording()
                                }
                            }
                            .onEnded { _ in
                                if speechRecognitionManager.isRecording {
                                    stopRecording()
                                } else if isSearching {
                                    stopSearch()
                                }
                            }
                    )
                    .accessibilityLabel(speechRecognitionManager.isRecording ? "Recording voice command" : isSearching ? "Stop searching" : "Hold to speak voice command")
                    .accessibilityHint(speechRecognitionManager.isRecording ? "Release to stop recording" : isSearching ? "Tap to stop search" : "Press and hold for 2 seconds to record voice command")
                }
                .padding(.horizontal)
                
                Text(statusMessage)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(statusMessage)
                
                if isSearching {
                    CameraView(
                        objectDetectionManager: objectDetectionManager,
                        spatialAudioManager: spatialAudioManager,
                        targetObject: searchText,
                        onObjectDetected: { object in
                            statusMessage = "Found \(object.label) at \(Int(object.azimuth))° \(object.azimuth > 0 ? "right" : "left")"
                            print("🎯 OBJECT DETECTED! Label: \(object.label), Azimuth: \(object.azimuth)°, Distance: \(object.distance)")
                            spatialAudioManager.playDirectionalSound(azimuth: object.azimuth, distance: object.distance)
                        }
                    )
                    .frame(height: 300)
                    .cornerRadius(15)
                    .padding()
                }
                
                Spacer()
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func startRecording() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            if !speechRecognitionManager.isRecording {
                speechRecognitionManager.startRecording()
                statusMessage = "Recording... say what you're looking for"
            }
        }
    }
    
    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        if speechRecognitionManager.isRecording {
            speechRecognitionManager.stopRecording()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !speechRecognitionManager.recognizedText.isEmpty {
                    searchText = speechRecognitionManager.recognizedText
                    print("🔊 Voice Command Processed: '\(self.searchText)'")
                    startSearch()
                } else {
                    print("🔊 No speech detected")
                    statusMessage = "No speech detected. Try again."
                }
            }
        }
    }
    
    private func startSearch() {
        isSearching = true
        statusMessage = "Searching for \(searchText)..."
        print("🔍 Search Started - Looking for: '\(searchText)'")
    }
    
    private func stopSearch() {
        isSearching = false
        spatialAudioManager.stopSound()
        statusMessage = "Search stopped"
    }
}