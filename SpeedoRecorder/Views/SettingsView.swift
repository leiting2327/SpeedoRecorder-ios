import SwiftUI

/// 设置页：地图数据源、API Key、速度单位、里程表清零、数据导出。
struct SettingsView: View {
    @EnvironmentObject var map: MapService
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var recorder: VideoRecorder

    @AppStorage("speedUnit") private var unitRaw: String = SpeedUnit.kmh.rawValue
    @AppStorage("speedLimit") private var speedLimit: Double = 120
    @AppStorage("overSpeedAlert") private var overSpeedAlert: Bool = true

    @State private var shareURLs: [URL] = []
    @State private var showShare = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("地图数据源") {
                    Picker("地图接口", selection: $map.provider) {
                        ForEach(MapProvider.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    if map.provider == .amap {
                        SecureField("高德 Web 服务 Key", text: $map.amapKey)
                        Text("在高德开放平台申请「Web 服务」类型 Key，用于逆地理与静态地图。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if map.provider == .baidu {
                        SecureField("百度 AK", text: $map.baiduKey)
                        Text("在百度开放平台申请服务端 AK，用于逆地理与静态地图。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("车速与告警") {
                    Picker("速度单位", selection: $unitRaw) {
                        ForEach(SpeedUnit.allCases) { u in
                            Text(u.rawValue).tag(u.rawValue)
                        }
                    }
                    Stepper("超速阈值：\(Int(speedLimit)) km/h", value: $speedLimit, in: 30...240, step: 10)
                    Toggle("超速提示", isOn: $overSpeedAlert)
                }

                Section("行程数据") {
                    Button("导出 CSV 轨迹表") { exportCSV() }
                    Button("导出 JSON 数据") { exportJSON() }
                    Button("清零本次里程与记录", role: .destructive) {
                        _ = location.endTrip()
                        message = "已清零"
                    }
                    if let message {
                        Text(message).font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    Text("车速、GPS 信号、位置与轨迹均来自系统定位；录制视频会把这些信息实时烧录到画面。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showShare) {
                ShareSheet(urls: shareURLs)
            }
        }
    }

    private var unit: SpeedUnit { SpeedUnit(rawValue: unitRaw) ?? .kmh }

    private func exportCSV() {
        let summary = TripSummary(
            startDate: location.samples.first?.timestamp ?? Date(),
            endDate: location.samples.last?.timestamp ?? Date(),
            maxSpeedKmh: location.maxSpeedKmh,
            avgSpeedKmh: location.samples.map(\.speedKmh).reduce(0, +) / Double(max(location.samples.count, 1)),
            distanceMeters: location.tripDistance,
            ascentMeters: location.tripAscent,
            sampleCount: location.samples.count,
            provider: "CoreLocation"
        )
        guard let url = TripExportService.shared.exportCSV(points: location.samples, summary: summary) else {
            message = "导出失败"
            return
        }
        shareURLs = [url]
        showShare = true
    }

    private func exportJSON() {
        let summary = TripSummary(
            startDate: location.samples.first?.timestamp ?? Date(),
            endDate: location.samples.last?.timestamp ?? Date(),
            maxSpeedKmh: location.maxSpeedKmh,
            avgSpeedKmh: location.samples.map(\.speedKmh).reduce(0, +) / Double(max(location.samples.count, 1)),
            distanceMeters: location.tripDistance,
            ascentMeters: location.tripAscent,
            sampleCount: location.samples.count,
            provider: "CoreLocation"
        )
        guard let url = TripExportService.shared.exportJSON(points: location.samples, summary: summary) else {
            message = "导出失败"
            return
        }
        shareURLs = [url]
        showShare = true
    }
}

/// 系统分享面板
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
