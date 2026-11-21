import SwiftUI

/// 设置页：地图数据源、API Key、速度单位、功能开关（默认全开）、数据导出。
struct SettingsView: View {
    @EnvironmentObject var map: MapService
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var recorder: VideoRecorder
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var health: HealthChecker

    @AppStorage("speedUnit") private var unitRaw: String = SpeedUnit.kmh.rawValue
    @AppStorage("speedLimit") private var speedLimit: Double = 120

    @State private var shareURLs: [URL] = []
    @State private var showShare = false
    @State private var message: String?
    @State private var previewImage: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section("功能开关（默认全部打开）") {
                    Toggle("摄像头画中画（叠加路况画面）", isOn: $settings.cameraPip)
                    Toggle("轨迹地图回放", isOn: $settings.trackReplay)
                    Toggle("指南针表盘与转向箭头", isOn: $settings.compass)
                    Toggle("分段小计与行程对比", isOn: $settings.tripCompare)
                    Toggle("录制同步环境音", isOn: $settings.audio)
                    Toggle("超速提示", isOn: $settings.overSpeedAlert)
                    Button("恢复全部默认开启") {
                        settings.resetToDefaults()
                        message = "已恢复默认（全部打开）"
                    }
                }

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
                }

                Section("行程数据") {
                    Button("导出 CSV 轨迹表") { exportCSV() }
                    Button("导出 JSON 数据") { exportJSON() }
                    Button("清零分段小计") {
                        location.resetSubTrip()
                        message = "小计已清零"
                    }
                    Button("清零本次里程与记录", role: .destructive) {
                        _ = location.endTrip()
                        message = "已清零"
                    }
                    if let message {
                        Text(message).font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("录制画面预览") {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 320)
                            .cornerRadius(20)
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 200)
                            .overlay(Text("预览生成中…").foregroundColor(.secondary).font(.caption))
                    }
                    Text("此预览与保存到相册的视频画面一致；下方可调整组件位置、大小、透明度。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Button("刷新预览") { refreshPreview() }
                }

                Section("画面布局（录制视频内组件）") {
                    LayoutSliderGroup(title: "车速组件", layout: settings.speedLayout) { newLayout in
                        settings.speedLayout = newLayout
                    }
                    LayoutSliderGroup(title: "起终点组件", layout: settings.routeLayout) { newLayout in
                        settings.routeLayout = newLayout
                    }
                }

                Section("自检与修复") {
                    Text(health.lastSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(health.items) { item in
                        HStack {
                            Image(systemName: Self.icon(for: item.status))
                                .foregroundColor(Self.color(for: item.status))
                            Text(item.name).font(.subheadline)
                            Spacer()
                            Text(item.detail).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Button("重新自检并自动修复") {
                        health.runChecks(settings: settings)
                        message = "自检已重新执行"
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
            .onAppear { refreshPreview() }
            .sheet(isPresented: $showShare) {
                ShareSheet(urls: shareURLs)
            }
        }
    }

    private func makeSummary() -> TripSummary {
        TripSummary(
            startDate: location.samples.first?.timestamp ?? Date(),
            endDate: location.samples.last?.timestamp ?? Date(),
            maxSpeedKmh: location.maxSpeedKmh,
            avgSpeedKmh: location.samples.map(\.speedKmh).reduce(0, +) / Double(max(location.samples.count, 1)),
            distanceMeters: location.tripDistance,
            ascentMeters: location.tripAscent,
            sampleCount: location.samples.count,
            provider: "CoreLocation"
        )
    }

    private func exportCSV() {
        guard let url = TripExportService.shared.exportCSV(points: location.samples, summary: makeSummary()) else {
            message = "导出失败"
            return
        }
        shareURLs = [url]
        showShare = true
    }

    private func exportJSON() {
        guard let url = TripExportService.shared.exportJSON(points: location.samples, summary: makeSummary()) else {
            message = "导出失败"
            return
        }
        shareURLs = [url]
        showShare = true
    }

    private func refreshPreview() {
        DispatchQueue.global(qos: .utility).async {
            let img = recorder.makePreviewImage()
            DispatchQueue.main.async { previewImage = img }
        }
    }

    private static func icon(for status: CheckItem.Status) -> String {
        switch status {
        case .ok: return "checkmark.circle"
        case .repaired: return "wrench.and.screwdriver"
        case .warning: return "exclamationmark.triangle"
        }
    }

    private static func color(for status: CheckItem.Status) -> Color {
        switch status {
        case .ok: return .green
        case .repaired: return .orange
        case .warning: return .yellow
        }
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

/// 单个组件的位置 / 大小 / 透明度滑块组
struct LayoutSliderGroup: View {
    let title: String
    let layout: ComponentLayout
    let onChange: (ComponentLayout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))

            sliderRow(label: "水平位置", value: Binding(
                get: { layout.centerX },
                set: { onChange(ComponentLayout(centerX: $0, centerY: layout.centerY, scale: layout.scale, opacity: layout.opacity)) }
            ), range: 0.05...0.95)

            sliderRow(label: "垂直位置", value: Binding(
                get: { layout.centerY },
                set: { onChange(ComponentLayout(centerX: layout.centerX, centerY: $0, scale: layout.scale, opacity: layout.opacity)) }
            ), range: 0.05...0.95)

            sliderRow(label: "大小", value: Binding(
                get: { layout.scale },
                set: { onChange(ComponentLayout(centerX: layout.centerX, centerY: layout.centerY, scale: $0, opacity: layout.opacity)) }
            ), range: 0.5...2.0)

            sliderRow(label: "透明度", value: Binding(
                get: { layout.opacity },
                set: { onChange(ComponentLayout(centerX: layout.centerX, centerY: layout.centerY, scale: layout.scale, opacity: $0)) }
            ), range: 0.1...1.0)
        }
        .padding(.vertical, 6)
    }

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
    }
}
