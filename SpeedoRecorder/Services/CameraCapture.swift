import Foundation
import AVFoundation
import UIKit
import CoreVideo

/// 后置摄像头采集：
/// - 提供实时预览图层供界面画中画显示；
/// - 保留最新一帧 CVPixelBuffer，供视频录制合成时作为底图。
final class CameraCapture: NSObject, ObservableObject {

    @Published var isAuthorized: Bool = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var videoOutput: AVCaptureVideoDataOutput?
    private var latestBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()

    /// 是否已启动
    private(set) var running = false

    /// 供预览图层绑定的会话
    var sessionForPreview: AVCaptureSession { session }

    // MARK: - 权限与启动
    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.startSession() }
                }
            }
        default:
            isAuthorized = false
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1920x1080

            // 后置摄像头
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                self.session.commitConfiguration()
                return
            }
            if self.session.canAddInput(input) { self.session.addInput(input) }

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: self.sessionQueue)
            if self.session.canAddOutput(output) { self.session.addOutput(output) }
            self.videoOutput = output

            self.session.commitConfiguration()
            self.session.startRunning()
            self.running = true

            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                self.previewLayer = layer
                self.isAuthorized = true
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            self.running = false
        }
    }

    /// 取最新一帧（返回自动释放的副本引用），无帧返回 nil。
    func currentPixelBuffer() -> CVPixelBuffer? {
        bufferLock.lock()
        let buf = latestBuffer
        bufferLock.unlock()
        return buf
    }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        bufferLock.lock()
        latestBuffer = pixelBuffer
        bufferLock.unlock()
    }
}
