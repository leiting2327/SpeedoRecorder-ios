import Foundation
import SwiftUI

/// 全部功能开关，默认打开；持久化到 UserDefaults。
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private init() {}

    /// 摄像头画中画：录制时叠加真实路况画面
    @AppStorage("featureCameraPip") var cameraPip: Bool = true
    /// 轨迹地图回放：行程结束后在地图上画出路线
    @AppStorage("featureTrackReplay") var trackReplay: Bool = true
    /// 指南针表盘与转向箭头
    @AppStorage("featureCompass") var compass: Bool = true
    /// 分段小计与行程对比
    @AppStorage("featureTripCompare") var tripCompare: Bool = true
    /// 录制同步环境音
    @AppStorage("featureAudio") var audio: Bool = true
    /// 超速提示
    @AppStorage("featureOverSpeedAlert") var overSpeedAlert: Bool = true

    /// 重置为默认（全部打开）
    func resetToDefaults() {
        cameraPip = true
        trackReplay = true
        compass = true
        tripCompare = true
        audio = true
        overSpeedAlert = true
    }
}
