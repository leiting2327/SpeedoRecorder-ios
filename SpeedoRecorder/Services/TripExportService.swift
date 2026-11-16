import Foundation
import UIKit
import Photos

/// 把行程轨迹导出为 CSV / JSON 文件，并把合成好的视频保存到相册。
final class TripExportService {

    static let shared = TripExportService()

    private init() {}

    /// 导出 CSV（Excel/表格软件可直接打开）
    func exportCSV(points: [TrackPoint], summary: TripSummary?) -> URL? {
        let dateFmt = ISO8601DateFormatter()
        var rows = ["时间戳,纬度,经度,海拔m,航向°,水平精度m,垂直精度m,速度m/s,速度km/h,GPS档位,累计里程m,累计爬升m,活动状态,来源"]
        for p in points {
            rows.append([
                dateFmt.string(from: p.timestamp),
                String(format: "%.6f", p.latitude),
                String(format: "%.6f", p.longitude),
                String(format: "%.1f", p.altitude),
                String(format: "%.1f", p.course),
                String(format: "%.1f", p.horizontalAccuracy),
                String(format: "%.1f", p.verticalAccuracy),
                String(format: "%.2f", p.speedMps),
                String(format: "%.1f", p.speedKmh),
                "\(p.gpsLevel)",
                String(format: "%.1f", p.distanceMeters),
                String(format: "%.1f", p.ascentMeters),
                p.activity,
                p.provider
            ].joined(separator: ","))
        }
        if let s = summary {
            rows.append("")
            rows.append("汇总:起始时间,结束时间,最高车速km/h,平均车速km/h,总里程m,总爬升m,采样点数,来源")
            rows.append([
                dateFmt.string(from: s.startDate),
                dateFmt.string(from: s.endDate),
                String(format: "%.1f", s.maxSpeedKmh),
                String(format: "%.1f", s.avgSpeedKmh),
                String(format: "%.1f", s.distanceMeters),
                String(format: "%.1f", s.ascentMeters),
                "\(s.sampleCount)",
                s.provider
            ].joined(separator: ","))
        }

        let fileName = "行程轨迹-\(Self.fileDate()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try rows.joined(separator: "\n").data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// 导出 JSON（结构化，含汇总）
    func exportJSON(points: [TrackPoint], summary: TripSummary?) -> URL? {
        struct Payload: Codable {
            let summary: TripSummary?
            let points: [TrackPoint]
        }
        let payload = Payload(summary: summary, points: points)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return nil }
        let fileName = "行程数据-\(Self.fileDate()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// 把视频保存到系统相册
    func saveVideoToAlbum(url: URL, completion: @escaping (Bool, Error?) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            Self.performSave(url: url, completion: completion)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { st in
                if st == .authorized || st == .limited {
                    Self.performSave(url: url, completion: completion)
                } else {
                    completion(false, nil)
                }
            }
        default:
            completion(false, nil)
        }
    }

    private static func performSave(url: URL, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { ok, err in
            DispatchQueue.main.async { completion(ok, err) }
        }
    }

    private static func fileDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
