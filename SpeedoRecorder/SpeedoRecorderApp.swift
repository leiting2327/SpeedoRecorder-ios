import SwiftUI

@main
struct SpeedoRecorderApp: App {
    @StateObject private var location = LocationManager()
    @StateObject private var map = MapService.shared
    @StateObject private var recorder = VideoRecorder()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var camera = CameraCapture()
    @StateObject private var mic = MicCapture()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(location)
                .environmentObject(map)
                .environmentObject(recorder)
                .environmentObject(settings)
                .environmentObject(camera)
                .environmentObject(mic)
        }
    }
}
