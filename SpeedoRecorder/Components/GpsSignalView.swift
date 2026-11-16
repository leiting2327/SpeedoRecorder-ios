import SwiftUI

/// GPS 信号强度条：4 格，颜色随档位变化。
struct GpsSignalView: View {
    let level: Int
    let description: String

    private let bars: [CGFloat] = [22, 34, 46, 58]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(i < level ? barColor : Color.white.opacity(0.18))
                    .frame(width: 14, height: bars[i])
            }
            Text(description)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var barColor: Color {
        switch level {
        case 4: return .green
        case 3: return .mint
        case 2: return .yellow
        case 1: return .orange
        default: return .red
        }
    }
}

/// 液态玻璃卡片容器。
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}
