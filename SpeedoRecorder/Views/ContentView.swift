import SwiftUI
import CoreLocation
import MapKit

struct ContentView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var map: MapService
    @EnvironmentObject var recorder: VideoRecorder

    @AppStorage("speedUnit") private var unitRaw: String = SpeedUnit.kmh.rawValue
    @AppStorage("speedLimit") private var speedLimit: Double = 120
    @AppStorage("overSpeedAlert") private var overSpeedAlert: Bool = true

    @State private var showSettings = false
    @State private var savedVideoURL: URL?
    @State private var showSavedAlert = false
    @State private var lastError: String?

    private var unit: SpeedUnit { SpeedUnit(rawValue: unitRaw) ?? .kmh }

    private var displaySpeed: Double {
        let kmh = location.speedKmh
        return unit == .mph ? kmh * 0.621371 : kmh
    }

    private var overSpeed: Bool {
        overSpeedAlert && location.speedKmh > speedLimit
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 纯黑背景
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 顶部：GPS + 时间 + 地图来源
                        topBar

                        // 大车速表
                        speedDial

                        // 副指标网格
                        metricsGrid

                        // 位置卡片（内嵌地图预览）
                        locationCard

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
            }
            .alert("视频已保存到相册", isPresented: $showSavedAlert) {
                Button("好", role: .cancel) {}
            }
            .onAppear {
                location.requestPermission()
                recorder.bind(location: location, map: map, unit: unit)
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
                // 简易速度刻度环
                SpeedArc(progress: min(location.speedKmh / 200, 1), over: overSpeed)
                    .frame(height: 24)
            }
            .frame(maxWidth: .infinity)
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

    // MARK: - 位置卡片
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
                if #available(iOS 17.0, *) {
                    MiniMap(coordinate: location.coordinate)
                        .frame(height: 160)
                        .cornerRadius(20)
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 160)
                        .cornerRadius(20)
                }
            }
        }
    }

    // MARK: - 录制控制
    private var recordControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 20) {
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
            recorder.stop { url in
                guard let url else {
                    lastError = "视频合成失败"
                    return
                }
                savedVideoURL = url
                TripExportService.shared.saveVideoToAlbum(url: url) { ok, _ in
                    if ok { showSavedAlert = true }
                    else { lastError = "保存相册失败，可在文件中查看" }
                }
                // 同时归档本次行程数据
                _ = TripExportService.shared.exportCSV(points: location.samples, summary: nil)
            }
        } else {
            do {
                lastError = nil
                try recorder.start()
            } catch {
                lastError = "无法开始录制：\(error.localizedDescription)"
            }
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

/// 内嵌地图预览（Apple MapKit；高德/百度 Key 用于逆地理与外链打开）
struct MiniMap: View {
    let coordinate: CLLocationCoordinate2D?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var lastLat: Double = 0
    @State private var lastLon: Double = 0

    var body: some View {
        Map(coordinateRegion: $region, showsUserLocation: true, userTrackingMode: .constant(.follow))
            .onChange(of: coordinate?.latitude ?? 0) { _, lat in
                updateRegion(lat: lat, lon: coordinate?.longitude ?? lastLon)
            }
            .onChange(of: coordinate?.longitude ?? 0) { _, lon in
                updateRegion(lat: coordinate?.latitude ?? lastLat, lon: lon)
            }
    }

    private func updateRegion(lat: Double, lon: Double) {
        guard abs(lat - lastLat) > 0.0001 || abs(lon - lastLon) > 0.0001 else { return }
        lastLat = lat; lastLon = lon
        region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    }
}
