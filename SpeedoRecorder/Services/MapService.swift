import Foundation
import CoreLocation
import Combine
import UIKit

/// 地图配置：高德 / 百度 REST API Key 由用户在设置页填入。
/// 选“系统地图”时使用 Apple Maps，无需 Key。
final class MapService: ObservableObject {

    static let shared = MapService()

    @Published var provider: MapProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "mapProvider") }
    }
    @Published var amapKey: String {
        didSet { UserDefaults.standard.set(amapKey, forKey: "amapKey") }
    }
    @Published var baiduKey: String {
        didSet { UserDefaults.standard.set(baiduKey, forKey: "baiduKey") }
    }
    /// 逆地理解析出的当前地址描述
    @Published var addressText: String = "定位中…"

    private var cancel = Set<AnyCancellable>()

    private init() {
        if let raw = UserDefaults.standard.string(forKey: "mapProvider"),
           let p = MapProvider(rawValue: raw) {
            self.provider = p
        } else {
            self.provider = .system
        }
        self.amapKey = UserDefaults.standard.string(forKey: "amapKey") ?? ""
        self.baiduKey = UserDefaults.standard.string(forKey: "baiduKey") ?? ""
    }

    // MARK: - 逆地理编码（坐标 -> 地址）
    func reverseGeocode(_ location: CLLocation) {
        switch provider {
        case .system:
            reverseWithApple(location)
        case .amap:
            reverseWithAmap(location)
        case .baidu:
            reverseWithBaidu(location)
        }
    }

    // Apple 系统逆地理（无 Key）
    private func reverseWithApple(_ location: CLLocation) {
        let geo = CLGeocoder()
        geo.reverseGeocodeLocation(location) { [weak self] places, _ in
            guard let self else { return }
            if let p = places?.first {
                let parts = [p.locality, p.subLocality, p.thoroughfare, p.name].compactMap { $0 }
                DispatchQueue.main.async { self.addressText = parts.joined(separator: " ") }
            } else {
                DispatchQueue.main.async { self.addressText = "暂无地址信息" }
            }
        }
    }

    // 高德 REST：https://restapi.amap.com/v3/geocode/regeo
    private func reverseWithAmap(_ location: CLLocation) {
        guard !amapKey.isEmpty,
              let url = URL(string: "https://restapi.amap.com/v3/geocode/regeo?key=\(amapKey)&location=\(location.coordinate.longitude),\(location.coordinate.latitude)&output=json&extensions=base")
        else {
            DispatchQueue.main.async { self.addressText = "未配置高德 Key" }
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let regeo = json["regeocode"] as? [String: Any],
                  let fmt = regeo["formatted_address"] as? String else {
                DispatchQueue.main.async { self?.addressText = "高德解析失败" }
                return
            }
            DispatchQueue.main.async { self?.addressText = fmt }
        }.resume()
    }

    // 百度 REST：https://api.map.baidu.com/reverse_geocoding/v3
    private func reverseWithBaidu(_ location: CLLocation) {
        guard !baiduKey.isEmpty,
              let url = URL(string: "https://api.map.baidu.com/reverse_geocoding/v3/?ak=\(baiduKey)&output=json&coordtype=wgs84ll&location=\(location.coordinate.latitude),\(location.coordinate.longitude)")
        else {
            DispatchQueue.main.async { self.addressText = "未配置百度 Key" }
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any],
                  let fmt = result["formatted_address"] as? String else {
                DispatchQueue.main.async { self?.addressText = "百度解析失败" }
                return
            }
            DispatchQueue.main.async { self?.addressText = fmt }
        }.resume()
    }

    // MARK: - 静态地图图块 URL（叠加到录制画面 / 预览小窗）
    /// 高德静态图
    func amapStaticImageURL(_ location: CLLocation, size: CGSize, zoom: Int = 16) -> URL? {
        guard !amapKey.isEmpty else { return nil }
        let marker = "mid,,A:\(location.coordinate.latitude),\(location.coordinate.longitude)"
        let str = "https://restapi.amap.com/v3/staticmap?key=\(amapKey)&location=\(location.coordinate.longitude),\(location.coordinate.latitude)&zoom=\(zoom)&size=\(Int(size.width))*\(Int(size.height))&markers=\(marker)"
        return URL(string: str)
    }

    /// 百度静态图
    func baiduStaticImageURL(_ location: CLLocation, size: CGSize, zoom: Int = 16) -> URL? {
        guard !baiduKey.isEmpty else { return nil }
        let str = "https://api.map.baidu.com/staticimage/v2?ak=\(baiduKey)&center=\(location.coordinate.longitude),\(location.coordinate.latitude)&width=\(Int(size.width))&height=\(Int(size.height))&zoom=\(zoom)&markers=\(location.coordinate.latitude),\(location.coordinate.longitude)"
        return URL(string: str)
    }

    /// 在外部地图 App 中打开当前位置（高德/百度/系统）
    func openExternalMap(_ location: CLLocation) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        switch provider {
        case .system:
            if let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lon)") {
                UIApplication.shared.open(url)
            }
        case .amap:
            if let url = URL(string: "iosamap://viewMap?sourceApplication=SpeedoRecorder&poiname=当前位置&lat=\(lat)&lon=\(lon)&dev=0") {
                UIApplication.shared.open(url)
            }
        case .baidu:
            if let url = URL(string: "baidumap://map/marker?location=\(lat),\(lon)&title=当前位置&src=SpeedoRecorder") {
                UIApplication.shared.open(url)
            }
        }
    }
}
