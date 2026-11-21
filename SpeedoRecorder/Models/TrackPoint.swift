import Foundation
import CoreLocation

/// 地图数据源选择（保留备用，当前界面未使用）
enum MapProvider: String, Codable, CaseIterable, Identifiable {
    case system = "系统地图"
    case amap = "高德地图"
    case baidu = "百度地图"

    var id: String { rawValue }
}

/// 速度单位
enum SpeedUnit: String, Codable, CaseIterable, Identifiable {
    case kmh = "km/h"
    case mph = "mph"
    var id: String { rawValue }
}
