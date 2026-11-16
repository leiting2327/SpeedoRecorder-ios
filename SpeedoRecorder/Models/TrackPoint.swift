import Foundation
import CoreLocation

/// 单条行程采样记录：会被写入 CSV/JSON，并在录制视频时叠加到画面上。
struct TrackPoint: Codable, Identifiable {
    var id: UUID = UUID()
    /// 毫秒时间戳
    let timestamp: Date
    /// 纬度
    let latitude: Double
    /// 经度
    let longitude: Double
    /// 海拔（米）
    let altitude: Double
    /// 航向（度，0~360）
    let course: Double
    /// 水平精度（米），越小越准
    let horizontalAccuracy: Double
    /// 垂直精度（米）
    let verticalAccuracy: Double
    /// 原始速度（m/s，来自 GPS）
    let speedMps: Double
    /// 显示速度（km/h，已按单位换算）
    let speedKmh: Double
    /// GPS 信号档位 0~4
    let gpsLevel: Int
    /// 累计里程（米）
    let distanceMeters: Double
    /// 海拔爬升（米）
    let ascentMeters: Double
    /// 系统活动状态：驾车/步行/骑行等
    let activity: String
    /// 原始位置更新来源
    let provider: String

    enum CodingKeys: String, CodingKey {
        case timestamp, latitude, longitude, altitude, course
        case horizontalAccuracy, verticalAccuracy, speedMps, speedKmh
        case gpsLevel, distanceMeters, ascentMeters, activity, provider
    }
}

/// 一次完整行程的汇总信息，导出数据时随轨迹一起保存。
struct TripSummary: Codable {
    let startDate: Date
    let endDate: Date
    let maxSpeedKmh: Double
    let avgSpeedKmh: Double
    let distanceMeters: Double
    let ascentMeters: Double
    let sampleCount: Int
    let provider: String
}

/// 地图数据源选择
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
