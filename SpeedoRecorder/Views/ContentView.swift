import SwiftUI
import CoreLocation
import MapKit
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var map: MapService
    @EnvironmentObject var recorder: VideoRecorder
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var camera: CameraCapture
    @EnvironmentObject var mic: MicCapture

    @AppStorage("speedUnit") private var unitRaw: String = SpeedUnit.kmh.rawValue
    @AppStorage("speedLimit") private var speedLimit: Double = 120

    @State private var showSettings = false
    @State private var savedVideoURL: URL?
    @State private var showSavedAlert = false
    @State private var lastError: String?
    @State private var showReplay = false

    private var unit: SpeedUnit { SpeedUnit(rawValue: unitRaw) ?? .kmh }

    private var displaySpeed: Double {
        let kmh = location.speedKmh
        return unit == .mph ? kmh * 0.621371 : kmh
    }

    private var overSpeed: Bool {
        settings.overSpeedAlert && location.speedKmh > speedLimit
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 纯黑背景
                Color.black.ignoresSafeArea()

                // 摄像头画中画背景（开关打开且有权限）
                if settings.cameraPip, camera.isAuthorized, camera.running {
                    CameraPreviewLayer()
                        .ignoresSafeArea()
                        .opacity(0.55)
                }

                ScrollView {
                    VStack(spacing: 20) {
                        // 顶部：GPS + 时间 + 地图来源
                        topBar

                        // 大车速表
                        speedDial

                        // 指南针 / 转向箭头（开关打开）
                        if settings.compass {
                            compassTile
                        }

                        // 副指标网格
                        metricsGrid

                        // 分段小计 + 上段对比（开关打开）
                        if settings.tripCompare {
                            compareGrid
                        }

                        // 位置卡片（内嵌地图预览）
                        locationCard

                        // 轨迹回放入口（开关打开）
                        if settings.trackReplay && !location.samples.isEmpty {
                            replayButton
                        }

                        // 录制控制
                        recordControls
                    }
                    .padding()
                }
            }
            .navigationTitle("车速记录仪")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(map)
                    .environmentObject(location)
                    .environmentObject(recorder)
                    .environmentObject(settings)
            }
            .sheet(isPresented: $showReplay) {
                TrackReplayContainer(points: location.samples)
            }
            .alert("视频已保存到相册", isPresented: $showSavedAlert) {
                Button("好", role: .cancel) {}
            }
            .onAppear {
                location.requestPermission()
                recorder.bind(location: location, map: map, unit: unit)
                // 摄像头/麦克风不在进入界面时自动拉起，仅在用户开始录制时按需启动
            }
            .onReceive(location.$lastLocation) { loc in
                guard let loc else { return }
                map.reverseGeocode(loc)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 顶部栏
    private var topBar: some View {
        HStack {
            GpsSignalView(level: location.gpsLevel, description: location.gpsDescription)
            Spacer()
            Text(map.provider.rawValue)
                .font(.caption)
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: - 车速表盘
    private var speedDial: some View {
        GlassCard {
            VStack(spacing: 8) {
                Text(String(format: "%.0f", displaySpeed))
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(overSpeed ? .red : .white)
                Text(unit.rawValue)
                    .font(.title2)
                    .foregroundColor(.secondary)
                if overSpeed {
                    Text("已超速 \(Int(location.speedKmh - speedLimit)) km/h")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                }
                SpeedArc(progress: min(location.speedKmh / 200, 1), over: overSpeed)
                    .frame(height: 24)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 指南针
    private var compassTile: some View {
        GlassCard {
            HStack(spacing: 20) {
                CompassDial(heading: location.heading)
                    .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 6) {
                    Text(compassDirection(location.heading))
                        .font(.title2.weight(.semibold))
                    Text(String(format: "航向 %.0f°", location.heading))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(turnArrow(location.heading))
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                Spacer()
            }
        }
    }

    // MARK: - 副指标
    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            MetricTile(title: "里程", value: String(format: "%.2f km", location.tripDistance / 1000))
            MetricTile(title: "海拔", value: String(format: "%.0f m", location.altitude))
            MetricTile(title: "航向", value: String(format: "%.0f°", location.heading))
            MetricTile(title: "累计爬升", value: String(format: "%.0f m", location.tripAscent))
            MetricTile(title: "最高车速", value: String(format: "%.0f %@", unit == .mph ? location.maxSpeedKmh * 0.621371 : location.maxSpeedKmh, unit.rawValue))
            MetricTile(title: "活动状态", value: location.activity)
        }
    }

    // MARK: - 分段小计 + 上段对比
    private var compareGrid: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("分段小计").font(.caption).foregroundColor(.secondary)
                        Text(String(format: "%.2f km", location.tripSubMeters / 1000))
                            .font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    Spacer()
                    Button("清零小计") { location.resetSubTrip() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
                if location.lastTripDistance > 0 {
                    Text(String(format: "上段：%.2f km · 最高 %.0f %@",
                                 location.lastTripDistance / 1000, location.lastTripMaxSpeed, unit.rawValue))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("暂无上段行程记录").font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 位置卡片
    @State private var showMiniMap = false

    private var locationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                    Text(map.addressText)
                        .font(.subheadline)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        if let loc = location.lastLocation { map.openExternalMap(loc) }
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                }
                if let coord = location.coordinate {
                    Text(String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
                        .font(.caption)
                        .monospaced()
                        .foregroundColor(.secondary)
                }
                // 地图懒加载：出现在屏幕上时才创建 MapKit 视图
                if showMiniMap {
                    MiniMap(coordinate: location.coordinate)
                        .frame(height: 160)
                        .cornerRadius(20)
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 160)
                        .cornerRadius(20)
                        .onAppear { showMiniMap = true }
                }
            }
        }
    }

    // MARK: - 轨迹回放
    private var replayButton: some View {
        Button {
            showReplay = true
        } label: {
            HStack {
                Image(systemName: "map")
                Text("查看本次轨迹回放（\(location.samples.count) 点）")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.headline)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    // MARK: - 录制控制
    private var recordControls: some View {
        VStack(spacing: 14) {
            Button {
                toggleRecord()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle")
                    Text(recorder.isRecording ? "停止并保存" : "开始录制")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(recorder.isRecording ? Color.red : Color.blue, in: RoundedRectangle(cornerRadius: 24))
            }

            if recorder.isRecording {
                HStack {
                    Text("REC")
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                    Text(String(format: "%02d:%02d", Int(recorder.recordDuration) / 60, Int(recorder.recordDuration) % 60))
                        .monospacedDigit()
                    Spacer()
                    Text("采样 \(location.samples.count) 点")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }

            if let lastError {
                Text(lastError).font(.caption).foregroundColor(.red)
            }
        }
    }

    private func toggleRecord() {
        if recorder.isRecording {
            mic.stop()
            recorder.stop { url in
                guard let url else {
                    DispatchQueue.main.async { lastError = "视频合成失败" }
                    return
                }
                savedVideoURL = url
                TripExportService.shared.saveVideoToAlbum(url: url) { ok, _ in
                    DispatchQueue.main.async {
                        if ok { showSavedAlert = true }
                        else { lastError = "保存相册失败，可在文件中查看" }
                    }
                }
                _ = TripExportService.shared.exportCSV(points: location.samples, summary: nil)
            }
        } else {
            lastError = nil
            recorder.camera = camera
            mic.attach(recorder: recorder)
            do {
                try recorder.start()
                if settings.audio { mic.requestAndStart() }
            } catch {
                recorder.stop { _ in }
                lastError = "无法开始录制：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 方向辅助
    private func compassDirection(_ heading: Double) -> String {
        let dirs = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let idx = Int((heading + 22.5) / 45) % 8
        return dirs[idx]
    }

    private func turnArrow(_ heading: Double) -> String {
        // 简易转向提示：根据航向角度给出箭头
        switch Int((heading + 22.5) / 45) % 8 {
        case 1: return "↗ 右前方"
        case 2: return "→ 正东"
        case 3: return "↘ 右后方"
        case 4: return "↓ 正南"
        case 5: return "↙ 左后方"
        case 6: return "← 正西"
        case 7: return "↖ 左前方"
        default: return "↑ 正北"
        }
    }
}

// MARK: - 摄像头预览图层
struct CameraPreviewLayer: UIViewRepresentable {
    @EnvironmentObject var camera: CameraCapture

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer?.session = camera.sessionForPreview
        view.videoPreviewLayer?.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer?.session = camera.sessionForPreview
    }


    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer? {
            layer as? AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - 小组件
struct MetricTile: View {
    let title: String
    let value: String
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundColor(.secondary)
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SpeedArc: View {
    let progress: Double
    let over: Bool
    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.white.opacity(0.12))
            Capsule()
                .fill(over ? Color.red : Color.green)
                .frame(width: geo.size.width * progress)
        }
    }
}

/// 表盘指南针（SwiftUI 绘制）
struct CompassDial: View {
    let heading: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 2)
            Text("N").font(.caption).foregroundColor(.red).offset(y: -42)
            Text("S").font(.caption).foregroundColor(.secondary).offset(y: 42)
            Text("W").font(.caption).foregroundColor(.secondary).offset(x: -42)
            Text("E").font(.caption).foregroundColor(.secondary).offset(x: 42)
            // 指针随航向旋转
            Image(systemName: "location.north.fill")
                .resizable()
                .frame(width: 22, height: 30)
                .foregroundColor(.blue)
                .rotationEffect(.degrees(heading))
        }
    }
}

/// 内嵌地图预览：用 UIKit MKMapView 包装，规避 SwiftUI Map 初始化器在新系统上的兼容问题
struct MiniMap: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .standard
        map.showsUserLocation = true
        map.isUserInteractionEnabled = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        guard let coord = coordinate, CLLocationCoordinate2DIsValid(coord) else { return }
        let region = MKCoordinateRegion(center: coord,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        map.setRegion(region, animated: true)
    }
}
