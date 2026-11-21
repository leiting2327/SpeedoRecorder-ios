import Foundation
import CoreLocation
import Combine

/// 实时定位管理：通过 CLLocationManager 的连续定位回调驱动车速、GPS 强度。
/// 不使用定时器轮询，位置一更新就刷新，做到“实时”。
final class LocationManager: NSObject, ObservableObject {

    // MARK: - 对外发布的实时状态
    @Published var lastLocation: CLLocation?
    @Published var speedMps: Double = 0
    @Published var speedKmh: Double = 0
    @Published var heading: Double = 0
    @Published var altitude: Double = 0
    @Published var horizontalAccuracy: Double = 0
    /// GPS 信号档位 0~4
    @Published var gpsLevel: Int = 0
    @Published var gpsDescription: String = "等待定位"
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// 本次行程累计里程（米）、累计爬升（米）、最高车速
    @Published var tripDistance: Double = 0
    @Published var tripAscent: Double = 0
    @Published var maxSpeedKmh: Double = 0

    private var manager: CLLocationManager?
    private var prevLocation: CLLocation?
    private var prevAltitude: Double?

    override init() {
        super.init()
        // 定位管理器延迟到首次需要时才创建，避免启动期拉起定位服务
    }

    private func ensureManager() -> CLLocationManager {
        if let m = manager { return m }
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBest
        m.distanceFilter = kCLDistanceFilterNone      // 任何位置变化都回调
        manager = m
        authorizationStatus = m.authorizationStatus
        return m
    }

    // MARK: - 权限与启动
    /// 首次进入界面时延迟调用，避免启动阶段触发权限弹窗/定位服务导致崩溃
    func requestPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startLocation()
        }
    }

    private func startLocation() {
        let m = ensureManager()
        let status = m.authorizationStatus
        if status == .notDetermined {
            m.requestWhenInUseAuthorization()
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways || status == .notDetermined else {
            gpsDescription = "定位权限未开启，请在系统设置中允许"
            return
        }
        m.startUpdatingLocation()
    }

    func stop() {
        manager?.stopUpdatingLocation()
        manager?.stopUpdatingHeading()
    }

    // MARK: - GPS 档位换算
    static func gpsLevel(accuracy: Double, hasFix: Bool) -> Int {
        guard hasFix, accuracy > 0 else { return 0 }
        switch accuracy {
        case ..<8: return 4
        case ..<20: return 3
        case ..<50: return 2
        case ..<100: return 1
        default: return 0
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        // 授权变为允许后再启动更新
        let st = manager.authorizationStatus
        if st == .authorizedWhenInUse || st == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // 过滤明显漂移的低精度点
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 200 else { return }

        let mps = location.speed >= 0 ? location.speed : 0
        let kmh = mps * 3.6

        // 里程累计
        if let prev = prevLocation {
            let step = location.distance(from: prev)
            if step > 0 && step < 500 {
                tripDistance += step
            }
        }
        // 爬升累计
        if let prevAlt = prevAltitude, location.altitude > prevAlt {
            tripAscent += location.altitude - prevAlt
        }
        prevAltitude = location.altitude
        prevLocation = location

        maxSpeedKmh = max(maxSpeedKmh, kmh)

        DispatchQueue.main.async {
            self.lastLocation = location
            self.coordinate = location.coordinate
            self.speedMps = mps
            self.speedKmh = kmh
            self.heading = location.course >= 0 ? location.course : self.heading
            self.altitude = location.altitude
            self.horizontalAccuracy = location.horizontalAccuracy
            let level = LocationManager.gpsLevel(accuracy: location.horizontalAccuracy, hasFix: true)
            self.gpsLevel = level
            self.gpsDescription = self.gpsText(level: level, accuracy: location.horizontalAccuracy)
        }
    }

    private func gpsText(level: Int, accuracy: Double) -> String {
        switch level {
        case 4: return "信号极佳 \(Int(accuracy))m"
        case 3: return "信号良好 \(Int(accuracy))m"
        case 2: return "信号一般 \(Int(accuracy))m"
        case 1: return "信号较弱 \(Int(accuracy))m"
        default: return "信号微弱 \(Int(accuracy))m"
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.gpsDescription = "定位失败：\(error.localizedDescription)"
        }
    }
}
