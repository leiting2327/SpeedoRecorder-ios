import Foundation
import SwiftUI

/// 全部功能开关，默认打开；持久化到 UserDefaults。
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private init() {}

    /// 超速提示
    @AppStorage("featureOverSpeedAlert") var overSpeedAlert: Bool = true

    /// 重置为默认
    func resetToDefaults() {
        overSpeedAlert = true
    }
}
