import SwiftUI

@main
struct SpeedoRecorderApp: App {
    @StateObject private var location = LocationManager()
    @StateObject private var map = MapService.shared
    @StateObject private var recorder = VideoRecorder()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(location)
                .environmentObject(map)
                .environmentObject(recorder)
        }
    }
}
