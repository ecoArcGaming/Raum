import SwiftUI

struct ContentView: View {
    @StateObject private var objectDetectionManager = ObjectDetectionManager()
    @StateObject private var spatialAudioManager = SpatialAudioManager()
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showCamera = false
    @State private var statusMessage = "Enter object to find"
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("SpatialNav")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityLabel("SpatialNav app")
                
                VStack(spacing: 20) {
                    TextField("What are you looking for?", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.title3)
                        .accessibilityLabel("Search field")
                        .accessibilityHint("Enter the object you want to find, for example: black Honda SUV")
                    
                    Button(action: startSearch) {
                        HStack {
                            Image(systemName: isSearching ? "stop.circle.fill" : "camera.fill")
                                .font(.title2)
                            Text(isSearching ? "Stop Search" : "Start Search")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(isSearching ? Color.red : Color.blue)
                        .cornerRadius(15)
                    }
                    .disabled(searchText.isEmpty)
                    .accessibilityLabel(isSearching ? "Stop searching" : "Start searching")
                    .accessibilityHint(isSearching ? "Tap to stop the search" : "Tap to start searching for the object")
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
    
    private func startSearch() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        if isSearching {
            isSearching = false
            spatialAudioManager.stopSound()
            statusMessage = "Search stopped"
        } else {
            isSearching = true
            statusMessage = "Searching for \(searchText)..."
        }
    }
}