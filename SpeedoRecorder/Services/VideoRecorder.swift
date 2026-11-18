import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import UIKit
import Combine

/// 行程视频录制器：
/// - 可选把后置摄像头实时画面作为底图，仪表/GPS/位置/里程等信息叠加在上层；
/// - 可选同步收录环境音；
/// - 每一帧都把当前车速、GPS 信号、地址、时间、里程、海拔、航向、指南针、小计等烧录进画面；
/// - 导出为 H.264 mp4，可保存到相册。
final class VideoRecorder: ObservableObject {

    @Published var isRecording: Bool = false
    @Published var recordDuration: TimeInterval = 0
    @Published var recordSize: Int64 = 0

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var displayLink: CADisplayLink?
    private var startTime: Date?
    private var frameCount: Int = 0
    private var outputURL: URL?

    /// 摄像头引用（可选注入）
    weak var camera: CameraCapture?
    /// 功能开关
    var settings: AppSettings = .shared

    /// 录制画布尺寸（竖屏）
    let canvasSize = CGSize(width: 1080, height: 1920)
    /// 帧率：跟随屏幕刷新（实时），不做固定 1 秒一帧
    private let fps: Int = 60

    @Published var currentSnapshot: Snapshot = Snapshot()
    private var cancellables = Set<AnyCancellable>()

    struct Snapshot {
        var speedKmh: Double = 0
        var unit: SpeedUnit = .kmh
        var gpsLevel: Int = 0
        var gpsText: String = ""
        var address: String = ""
        var latitude: Double = 0
        var longitude: Double = 0
        var altitude: Double = 0
        var heading: Double = 0
        var distanceMeters: Double = 0
        var tripSubMeters: Double = 0
        var ascentMeters: Double = 0
        var activity: String = ""
        var maxSpeed: Double = 0
        var prevDistance: Double = 0
        var prevMaxSpeed: Double = 0
        var sampleCount: Int = 0
        var timestamp: Date = Date()
        var providerName: String = "CoreLocation"
    }

    /// 订阅定位与地图服务，持续刷新录制画面用到的数据
    func bind(location: LocationManager, map: MapService, unit: SpeedUnit) {
        location.$speedKmh
            .combineLatest(location.$gpsLevel)
            .combineLatest(location.$gpsDescription)
            .combineLatest(location.$altitude)
            .combineLatest(location.$heading)
            .combineLatest(location.$tripDistance)
            .combineLatest(location.$tripAscent)
            .combineLatest(location.$activity)
            .combineLatest(location.$maxSpeedKmh)
            .combineLatest(location.$coordinate)
        .map { values in
            let (v9, coord) = values
            let (v8, maxSp) = v9
            let (v7, act) = v8
            let (v6, asc) = v7
            let (v5, dist) = v6
            let (v4, hd) = v5
            let (v3, alt) = v4
            let (v2, gps) = v3
            let (s, lvl) = v2
            return Snapshot(speedKmh: s, unit: unit, gpsLevel: lvl, gpsText: gps,
                     address: map.addressText,
                     latitude: coord?.latitude ?? 0, longitude: coord?.longitude ?? 0,
                     altitude: alt, heading: hd, distanceMeters: dist,
                     tripSubMeters: location.tripSubMeters,
                     ascentMeters: asc, activity: act, maxSpeed: maxSp,
                     prevDistance: location.lastTripDistance,
                     prevMaxSpeed: location.lastTripMaxSpeed,
                     sampleCount: location.samples.count,
                     timestamp: Date(),
                     providerName: map.provider.rawValue)
        }
        .assign(to: \.currentSnapshot, on: self)
        .store(in: &cancellables)
    }

    // MARK: - 开始 / 停止
    func start() throws {
        // 清理上一次残留
        displayLink?.invalidate()
        displayLink = nil
        writer = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil

        let fileName = "行程视频-\(Self.fileDate()).mp4"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        outputURL = url

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoConfig: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: canvasSize.width,
            AVVideoHeightKey: canvasSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoMaxKeyFrameIntervalKey: fps
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoConfig)
        input.expectsMediaDataInRealTime = true

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: canvasSize.width,
            kCVPixelBufferHeightKey as String: canvasSize.height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)

        writer.add(input)

        // 环境音轨道（开关打开时）
        if settings.audio {
            let audioConfig: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128_000,
                AVNumberOfChannelsKey: 2
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioConfig)
            aInput.expectsMediaDataInRealTime = true
            writer.add(aInput)
            self.audioInput = aInput
        }

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "VideoRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法开始写入"])
        }
        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor
        self.frameCount = 0
        self.startTime = nil
        self.recordDuration = 0
        self.recordSize = 0

        let link = CADisplayLink(target: self, selector: #selector(renderFrame))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(fps / 2), maximum: Float(fps), preferred: Float(fps))
        link.add(to: .main, forMode: .common)
        self.displayLink = link

        isRecording = true
    }

    func stop(completion: @escaping (URL?) -> Void) {
        displayLink?.invalidate()
        displayLink = nil
        guard let writer, let input = videoInput else {
            isRecording = false
            completion(nil)
            return
        }
        input.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isRecording = false
                if writer.status == .completed, let url = self.outputURL {
                    self.recordSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    completion(url)
                } else {
                    completion(nil)
                }
            }
        }
    }

    /// 追加音频样本（由麦克风采集器调用）
    func appendAudio(_ sample: CMSampleBuffer) {
        guard let audioInput, audioInput.isReadyForMoreMediaData else { return }
        guard CMSampleBufferIsValid(sample) else { return }
        audioInput.append(sample)
    }

    // MARK: - 逐帧渲染
    @objc private func renderFrame() {
        guard let writer, writer.status == .writing,
              let adaptor = pixelBufferAdaptor,
              let input = videoInput,
              input.isReadyForMoreMediaData else { return }

        let now = Date()
        if startTime == nil { startTime = now }
        guard let start = startTime else { return }
        let elapsed = now.timeIntervalSince(start)
        recordDuration = elapsed

        guard let buffer = makePixelBuffer() else { return }
        renderInto(buffer, snapshot: currentSnapshot, elapsed: elapsed)

        let time = CMTime(seconds: max(elapsed, 0), preferredTimescale: CMTimeScale(fps))
        if adaptor.append(buffer, withPresentationTime: time) {
            frameCount += 1
        }
    }

    private func makePixelBuffer() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ] as CFDictionary
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(canvasSize.width), Int(canvasSize.height),
                                         kCVPixelFormatType_32BGRA, attrs, &buffer)
        return status == kCVReturnSuccess ? buffer : nil
    }

    /// 把信息绘制进帧缓冲：摄像头底图（可选）+ 深色遮罩 + 液态玻璃仪表卡片。
    private func renderInto(_ buffer: CVPixelBuffer, snapshot: Snapshot, elapsed: TimeInterval) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                  width: Int(canvasSize.width),
                                  height: Int(canvasSize.height),
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return }

        let w = canvasSize.width
        let h = canvasSize.height

        // 底图：摄像头画面（开关打开且有帧），否则纯黑
        if settings.cameraPip, let cam = camera, let camBuf = cam.currentPixelBuffer() {
            drawCameraFrame(ctx: ctx, buffer: camBuf)
            // 压暗遮罩，保证仪表可读
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        } else {
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }

        // 顶部时间条
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "yyyy-MM-dd  HH:mm:ss"
        drawText(context: ctx, text: timeFmt.string(from: snapshot.timestamp),
                 at: CGPoint(x: 60, y: 80), font: UIFont.systemFont(ofSize: 44, weight: .medium),
                 color: .white)

        // 录制红点 + 时长
        if isRecording {
            ctx.setFillColor(UIColor.systemRed.cgColor)
            ctx.fillEllipse(in: CGRect(x: w - 220, y: 88, width: 36, height: 36))
            drawText(context: ctx, text: String(format: "REC %02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60),
                     at: CGPoint(x: w - 170, y: 80), font: UIFont.monospacedDigitSystemFont(ofSize: 40, weight: .semibold),
                     color: .white)
        }

        // 大车速表（液态玻璃卡片）
        let card = CGRect(x: 60, y: 220, width: w - 120, height: 620)
        drawGlassCard(context: ctx, rect: card)

        let speedText = String(format: "%.0f", displayedSpeed(snapshot))
        drawCenteredText(context: ctx, text: speedText, in: CGRect(x: card.minX, y: card.minY + 90, width: card.width, height: 320),
                         font: UIFont.systemFont(ofSize: 220, weight: .heavy), color: .white)
        drawCenteredText(context: ctx, text: snapshot.unit.rawValue,
                         in: CGRect(x: card.minX, y: card.minY + 420, width: card.width, height: 90),
                         font: UIFont.systemFont(ofSize: 64, weight: .medium), color: .secondaryLabel)

        // 指南针 + 转向箭头（开关打开）
        if settings.compass {
            drawCompass(context: ctx, heading: snapshot.heading,
                        in: CGRect(x: card.maxX - 200, y: card.minY + 30, width: 150, height: 150))
        }

        // 左右副指标
        let halfW = (w - 160) / 2
        let left = CGRect(x: 60, y: 900, width: halfW, height: 260)
        let right = CGRect(x: 100 + halfW, y: 900, width: halfW, height: 260)
        drawGlassCard(context: ctx, rect: left)
        drawGlassCard(context: ctx, rect: right)
        drawMetric(context: ctx, title: "里程", value: String(format: "%.2f km", snapshot.distanceMeters / 1000), in: left)
        drawMetric(context: ctx, title: "海拔", value: String(format: "%.0f m", snapshot.altitude), in: right)

        // 分段小计 + 上一段对比（开关打开）
        if settings.tripCompare {
            let subCard = CGRect(x: 60, y: 1200, width: w - 120, height: 220)
            drawGlassCard(context: ctx, rect: subCard)
            drawText(context: ctx, text: "小计", at: CGPoint(x: subCard.minX + 50, y: subCard.minY + 40),
                     font: UIFont.systemFont(ofSize: 36, weight: .medium), color: .secondaryLabel)
            drawText(context: ctx, text: String(format: "%.2f km", snapshot.tripSubMeters / 1000),
                     at: CGPoint(x: subCard.minX + 50, y: subCard.minY + 110),
                     font: UIFont.systemFont(ofSize: 52, weight: .bold), color: .white)
            let prevText = snapshot.prevDistance > 0
                ? String(format: "上段 %.2f km · 最高 %.0f %@", snapshot.prevDistance / 1000, snapshot.prevMaxSpeed, snapshot.unit.rawValue)
                : "暂无上段记录"
            drawText(context: ctx, text: prevText,
                     at: CGPoint(x: subCard.minX + 380, y: subCard.minY + 90),
                     font: UIFont.systemFont(ofSize: 34, weight: .regular), color: .secondaryLabel,
                     maxWidth: subCard.width - 430)
        }

        // GPS 信号卡
        let gpsY: CGFloat = settings.tripCompare ? 1460 : 1200
        let gpsCard = CGRect(x: 60, y: gpsY, width: w - 120, height: 220)
        drawGlassCard(context: ctx, rect: gpsCard)
        drawGpsBars(context: ctx, level: snapshot.gpsLevel, in: CGRect(x: gpsCard.minX + 50, y: gpsCard.minY + 60, width: 220, height: 100))
        drawText(context: ctx, text: "GPS \(snapshot.gpsText)", at: CGPoint(x: gpsCard.minX + 310, y: gpsCard.minY + 70),
                 font: UIFont.systemFont(ofSize: 46, weight: .semibold), color: .white)

        // 位置信息卡
        let locY: CGFloat = gpsY + 260
        let locCard = CGRect(x: 60, y: locY, width: w - 120, height: 260)
        drawGlassCard(context: ctx, rect: locCard)
        drawText(context: ctx, text: "📍 \(snapshot.address)", at: CGPoint(x: locCard.minX + 50, y: locCard.minY + 40),
                 font: UIFont.systemFont(ofSize: 40, weight: .medium), color: .white, maxWidth: locCard.width - 100)
        drawText(context: ctx, text: String(format: "%.6f, %.6f", snapshot.latitude, snapshot.longitude),
                 at: CGPoint(x: locCard.minX + 50, y: locCard.minY + 120),
                 font: UIFont.monospacedDigitSystemFont(ofSize: 38, weight: .regular), color: .secondaryLabel)
        drawText(context: ctx, text: String(format: "航向 %.0f° · 爬升 %.0f m · 活动 %@ · 最高 %.0f %@ · 采样 %d",
                                   snapshot.heading, snapshot.ascentMeters, snapshot.activity,
                                   snapshot.maxSpeed, snapshot.unit.rawValue, snapshot.sampleCount),
                 at: CGPoint(x: locCard.minX + 50, y: locCard.minY + 185),
                 font: UIFont.systemFont(ofSize: 32, weight: .regular), color: .secondaryLabel, maxWidth: locCard.width - 100)

        // 底部水印
        drawCenteredText(context: ctx, text: "SpeedoRecorder · \(snapshot.providerName)",
                         in: CGRect(x: 60, y: h - 120, width: w - 120, height: 60),
                         font: UIFont.systemFont(ofSize: 30, weight: .regular), color: .tertiaryLabel)
    }

    /// 把摄像头帧按填充方式绘制到画布
    private func drawCameraFrame(ctx: CGContext, buffer: CVPixelBuffer) {
        let ci = CIImage(cvPixelBuffer: buffer)
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: canvasSize.width / ci.extent.width,
                                                          y: canvasSize.height / ci.extent.height))
        let context = CIContext()
        if let cg = context.createCGImage(scaled, from: scaled.extent) {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height))
        }
    }

    private func displayedSpeed(_ s: Snapshot) -> Double {
        s.unit == .mph ? s.speedKmh * 0.621371 : s.speedKmh
    }

    // MARK: - 绘制辅助
    private func drawGlassCard(context ctx: CGContext, rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 44)
        ctx.saveGState()
        ctx.setFillColor(UIColor(white: 1, alpha: 0.08).cgColor)
        path.fill()
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.18).cgColor)
        ctx.setLineWidth(2)
        path.stroke()
        let highlight = CGRect(x: rect.minX + 20, y: rect.minY + 12, width: rect.width - 40, height: 2)
        ctx.setFillColor(UIColor(white: 1, alpha: 0.25).cgColor)
        ctx.fill(highlight)
        ctx.restoreGState()
    }

    private func drawMetric(context ctx: CGContext, title: String, value: String, in rect: CGRect) {
        drawCenteredText(context: ctx, text: title, in: CGRect(x: rect.minX, y: rect.minY + 40, width: rect.width, height: 70),
                         font: UIFont.systemFont(ofSize: 40, weight: .medium), color: .secondaryLabel)
        drawCenteredText(context: ctx, text: value, in: CGRect(x: rect.minX, y: rect.minY + 120, width: rect.width, height: 100),
                         font: UIFont.systemFont(ofSize: 56, weight: .bold), color: .white)
    }

    private func drawGpsBars(context ctx: CGContext, level: Int, in rect: CGRect) {
        let barW: CGFloat = 34
        let gap: CGFloat = 16
        for i in 0..<4 {
            let bh: CGFloat = 30 + CGFloat(i) * 22
            let x = rect.minX + CGFloat(i) * (barW + gap)
            let y = rect.maxY - bh
            let on = i < level
            ctx.setFillColor(on ? UIColor.systemGreen.cgColor : UIColor(white: 0.3, alpha: 1).cgColor)
            let bar = CGRect(x: x, y: y, width: barW, height: bh)
            let p = UIBezierPath(roundedRect: bar, cornerRadius: 8)
            p.fill()
        }
    }

    /// 指南针表盘：指针随航向旋转，标 N/E/S/W。
    private func drawCompass(context ctx: CGContext, heading: Double, in rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 6
        ctx.saveGState()
        // 外圈
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.25).cgColor)
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

        let dirs: [(String, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
        for (label, deg) in dirs {
            let rad = (deg - 90) * .pi / 180
            let px = center.x + cos(rad) * (radius - 18)
            let py = center.y + sin(rad) * (radius - 18)
            let attr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: label == "N" ? UIColor.systemRed : UIColor.white
            ]
            let att = NSAttributedString(string: label, attributes: attr)
            let size = att.size()
            att.draw(in: CGRect(x: px - size.width / 2, y: py - size.height / 2, width: size.width, height: size.height))
        }

        // 指针（指向当前航向）
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: CGFloat(heading * .pi / 180))
        let pointer = UIBezierPath()
        pointer.move(to: CGPoint(x: 0, y: -radius + 10))
        pointer.addLine(to: CGPoint(x: 12, y: 0))
        pointer.addLine(to: CGPoint(x: 0, y: radius - 20))
        pointer.addLine(to: CGPoint(x: -12, y: 0))
        pointer.close()
        ctx.setFillColor(UIColor.systemBlue.cgColor)
        pointer.fill()
        ctx.restoreGState()

        // 航向数字
        drawCenteredText(context: ctx, text: String(format: "%.0f°", heading),
                         in: CGRect(x: rect.minX, y: rect.maxY - 40, width: rect.width, height: 36),
                         font: UIFont.systemFont(ofSize: 26, weight: .medium), color: .white)
    }

    private func drawText(context ctx: CGContext, text: String, at point: CGPoint,
                          font: UIFont, color: UIColor, maxWidth: CGFloat? = nil) {
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let att = NSAttributedString(string: text, attributes: attr)
        let size = att.size()
        var drawW = size.width
        if let maxWidth, size.width > maxWidth { drawW = maxWidth }
        let rect = CGRect(x: point.x, y: point.y, width: drawW, height: size.height + 20)
        att.draw(in: rect)
    }

    private func drawCenteredText(context ctx: CGContext, text: String, in rect: CGRect,
                                  font: UIFont, color: UIColor) {
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let att = NSAttributedString(string: text, attributes: attr)
        let size = att.size()
        let x = rect.minX + (rect.width - size.width) / 2
        let y = rect.minY + (rect.height - size.height) / 2
        att.draw(in: CGRect(x: x, y: y, width: size.width, height: size.height))
    }

    private static func fileDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
