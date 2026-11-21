import SwiftUI

/// 设置页：速度单位、超速阈值、自检与修复。
struct SettingsView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var health: HealthChecker

    @AppStorage("speedUnit") private var unitRaw: String = SpeedUnit.kmh.rawValue
    @AppStorage("speedLimit") private var speedLimit: Double = 120

    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("车速与告警") {
                    Picker("速度单位", selection: $unitRaw) {
                        ForEach(SpeedUnit.allCases) { u in
                            Text(u.rawValue).tag(u.rawValue)
                        }
                    }
                    Toggle("超速提示", isOn: $settings.overSpeedAlert)
                    Stepper("超速阈值：\(Int(speedLimit)) km/h", value: $speedLimit, in: 30...240, step: 10)
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
                    if let message {
                        Text(message).font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    Text("车速、GPS 信号强度均来自系统定位。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
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
