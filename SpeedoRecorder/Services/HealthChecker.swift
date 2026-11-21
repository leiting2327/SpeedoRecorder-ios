import Foundation
import CoreLocation

/// 自检结果项
struct CheckItem: Identifiable {
    let id = UUID()
    let name: String
    let status: Status
    let detail: String

    enum Status {
        case ok
        case repaired
        case warning
    }
}

/// 每次打开 App 执行一次自检：检查定位权限状态、临时目录是否可用；
/// 对可自动修复的项（配置缺失）直接补默认，不依赖用户操作。
final class HealthChecker: ObservableObject {

    static let shared = HealthChecker()

    @Published var items: [CheckItem] = []
    @Published var lastSummary: String = "尚未自检"
    @Published var didRepair = false

    private init() {}

    /// 执行自检与自动修复，返回检查结果
    @discardableResult
    func runChecks(settings: AppSettings) -> [CheckItem] {
        var result: [CheckItem] = []
        var repaired = false

        // 1. 定位权限
        let locStatus = CLLocationManager().authorizationStatus
        switch locStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            result.append(CheckItem(name: "定位权限", status: .ok, detail: "已允许"))
        case .notDetermined:
            result.append(CheckItem(name: "定位权限", status: .warning, detail: "尚未授权，使用时会请求"))
        default:
            result.append(CheckItem(name: "定位权限", status: .warning, detail: "已被拒绝，需在系统设置开启"))
        }

        // 2. 临时存储目录可写
        let tmp = FileManager.default.temporaryDirectory
        let probe = tmp.appendingPathComponent("health-probe-\(UUID().uuidString)")
        do {
            try "ok".write(to: probe, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: probe)
            result.append(CheckItem(name: "存储目录", status: .ok, detail: "可读写"))
        } catch {
            result.append(CheckItem(name: "存储目录", status: .warning, detail: "临时目录不可写"))
        }

        // 3. 功能开关完整性：若开关值缺失，补默认
        if !Self.boolStored("featureOverSpeedAlert") {
            settings.overSpeedAlert = true; repaired = true
        }

        items = result
        didRepair = repaired
        let okCount = result.filter { $0.status == .ok }.count
        let warnCount = result.filter { $0.status == .warning }.count
        lastSummary = repaired
            ? "自检完成：已自动修复 \(result.filter { $0.status == .repaired }.count) 项，\(warnCount) 项需手动处理"
            : "自检完成：\(okCount) 项正常，\(warnCount) 项需关注"
        return result
    }

    private static func boolStored(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) is Bool
    }
}
