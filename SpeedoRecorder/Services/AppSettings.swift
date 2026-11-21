import Foundation
import SwiftUI

/// 单个画面组件的布局配置：位置（相对画布比例 0~1）、大小缩放、透明度。
struct ComponentLayout: Codable {
    /// 中心点 X，相对画布宽度 0~1
    var centerX: Double
    /// 中心点 Y，相对画布高度 0~1
    var centerY: Double
    /// 大小缩放系数 0.5~2.0
    var scale: Double
    /// 透明度 0.1~1.0
    var opacity: Double

    static let speedDefault = ComponentLayout(centerX: 0.5, centerY: 0.28, scale: 1.0, opacity: 1.0)
    static let routeDefault = ComponentLayout(centerX: 0.5, centerY: 0.86, scale: 1.0, opacity: 1.0)
}

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

    // MARK: - 画面组件布局（车速组件 / 起终点组件）
    /// 车速组件布局，存为 JSON
    @AppStorage("layoutSpeedComponent") private var speedLayoutData: Data = Data()
    /// 起终点组件布局，存为 JSON
    @AppStorage("layoutRouteComponent") private var routeLayoutData: Data = Data()

    var speedLayout: ComponentLayout {
        get { Self.decode(speedLayoutData, fallback: .speedDefault) }
        set { speedLayoutData = Self.encode(newValue) }
    }

    var routeLayout: ComponentLayout {
        get { Self.decode(routeLayoutData, fallback: .routeDefault) }
        set { routeLayoutData = Self.encode(newValue) }
    }

    /// 重置为默认（全部打开 + 布局复位）
    func resetToDefaults() {
        cameraPip = true
        trackReplay = true
        compass = true
        tripCompare = true
        audio = true
        overSpeedAlert = true
        speedLayoutData = Data()
        routeLayoutData = Data()
    }

    private static func encode(_ layout: ComponentLayout) -> Data {
        (try? JSONEncoder().encode(layout)) ?? Data()
    }

    private static func decode(_ data: Data, fallback: ComponentLayout) -> ComponentLayout {
        guard !data.isEmpty, let v = try? JSONDecoder().decode(ComponentLayout.self, from: data) else {
            return fallback
        }
        return v
    }
}
