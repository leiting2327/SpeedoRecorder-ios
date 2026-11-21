import SwiftUI

@main
struct SpeedoRecorderApp: App {
    @StateObject private var location = LocationManager()
    @StateObject private var map = MapService.shared
    @StateObject private var recorder = VideoRecorder()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var camera = CameraCapture()
    @StateObject private var mic = MicCapture()

    init() {
        // 捕获未处理的 ObjC 异常，便于在控制台定位；不覆盖系统信号处理
        NSSetUncaughtExceptionHandler { exception in
            NSLog("未捕获异常: \(exception.name.rawValue) — \(exception.reason ?? "")")
            NSLog("调用栈:\n\(exception.callStackSymbols.joined(separator: "\n"))")
        }
    }

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
