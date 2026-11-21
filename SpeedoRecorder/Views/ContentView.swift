import SwiftUI
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var health: HealthChecker

    @AppStorage("speedUnit") private var unitRaw: String = SpeedUnit.kmh.rawValue
    @AppStorage("speedLimit") private var speedLimit: Double = 120

    @State private var showSettings = false
    @State private var lastError: String?
    /// 开机演示动画当前演示车速（0 → 25 → 0），动画结束后回到真实车速
    @State private var demoSpeed: Double = 0
    @State private var demoDone = false

    private var unit: SpeedUnit { SpeedUnit(rawValue: unitRaw) ?? .kmh }

    private var displaySpeed: Double {
        let kmh = location.speedKmh
        return unit == .mph ? kmh * 0.621371 : kmh
    }

    private var overSpeed: Bool {
        settings.overSpeedAlert && location.speedKmh > speedLimit
    }

    /// 开机演示动画：表盘从 0 升到 25，再回到 0，之后接入真实车速
    private func runDemoAnimation() {
        demoDone = false
        demoSpeed = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 1.1)) { demoSpeed = 25 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.easeInOut(duration: 1.1)) { demoSpeed = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    demoDone = true
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 纯黑背景
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    // 顶部：GPS 信号
                    topBar

                    // 自检状态条
                    healthBar

                    Spacer()

                    // 大车速表
                    speedDial

                    Spacer()

                    // 底部次要指标
                    metricsRow
                }
                .padding()
            }
            .navigationTitle("车速表")
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
                    .environmentObject(location)
                    .environmentObject(settings)
            }
            .onAppear {
                location.requestPermission()
                // 每次打开自检并自动修复可恢复项
                health.runChecks(settings: settings)
                runDemoAnimation()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 自检状态条
    private var healthBar: some View {
        HStack(spacing: 8) {
            Image(systemName: health.didRepair ? "wrench.and.screwdriver" : "checkmark.shield")
                .foregroundColor(health.didRepair ? .orange : .green)
            Text(health.lastSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 顶部栏
    private var topBar: some View {
        HStack {
            GpsSignalView(level: location.gpsLevel, description: location.gpsDescription)
            Spacer()
        }
    }

    // MARK: - 车速表盘
    private var displayedDialSpeed: Double { demoDone ? displaySpeed : demoSpeed }

    private var speedDial: some View {
        GlassCard {
            VStack(spacing: 8) {
                Text(String(format: "%.0f", displayedDialSpeed))
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
                SpeedArc(progress: min(displayedDialSpeed / 200, 1), over: overSpeed)
                    .frame(height: 110)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 底部次要指标
    private var metricsRow: some View {
        HStack(spacing: 16) {
            MetricTile(title: "里程", value: String(format: "%.2f km", location.tripDistance / 1000))
            MetricTile(title: "海拔", value: String(format: "%.0f m", location.altitude))
            MetricTile(title: "最高车速", value: String(format: "%.0f %@", unit == .mph ? location.maxSpeedKmh * 0.621371 : location.maxSpeedKmh, unit.rawValue))
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

/// 车速扇形进度：上半圆弧形刻度，按进度填充扇形弧
struct SpeedArc: View {
    let progress: Double
    let over: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let radius = min(width, height)
            let center = CGPoint(x: width / 2, y: height)
            let clamped = min(max(progress, 0), 1)

            ZStack {
                // 背景半圆弧
                Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 14)

                // 进度扇形弧
                Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: .degrees(180),
                             endAngle: .degrees(180 - 180 * clamped),
                             clockwise: false)
                }
                .stroke(over ? Color.red : Color.green, lineWidth: 14)

                // 进度端点圆点
                Circle()
                    .fill(over ? Color.red : Color.green)
                    .frame(width: 14, height: 14)
                    .position(
                        x: center.x + radius * cos(Angle(degrees: 180 - 180 * clamped).radians),
                        y: center.y - radius * sin(Angle(degrees: 180 - 180 * clamped).radians)
                    )
            }
        }
    }
}
