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
        // 捕获未处理异常，避免直接闪退且便于在控制台定位
        NSSetUncaughtExceptionHandler { exception in
            NSLog("未捕获异常: \(exception.name.rawValue) — \(exception.reason ?? "")")
            NSLog("调用栈:\n\(exception.callStackSymbols.joined(separator: "\n"))")
        }
        SignalHandler.install()
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

/// 捕获 Swift 端未识别的信号（尽量记录，避免静默闪退）
enum SignalHandler {
    static func install() {
        let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE]
        for sig in signals {
            signal(sig) { code in
                NSLog("信号崩溃: \(code)")
            }
        }
    }
}
