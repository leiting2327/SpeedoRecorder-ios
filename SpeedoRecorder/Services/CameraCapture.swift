import Foundation
import AVFoundation
import UIKit
import CoreVideo

/// 后置摄像头采集：
/// - 提供实时预览图层供界面画中画显示；
/// - 保留最新一帧 CVPixelBuffer，供视频录制合成时作为底图。
/// 所有会话操作走串行队列，权限/设备不可用时安全降级，不抛异常。
final class CameraCapture: NSObject, ObservableObject {

    @Published var isAuthorized: Bool = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session", qos: .userInitiated)
    private var videoOutput: AVCaptureVideoDataOutput?
    private var latestBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()
    private var configured = false

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
            DispatchQueue.main.async { self.isAuthorized = false }
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.configured else {
                self.session.startRunning()
                self.running = true
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .medium

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                self.session.commitConfiguration()
                return
            }
            guard let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: self.sessionQueue)
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
                self.videoOutput = output
            }

            self.session.commitConfiguration()
            self.configured = true
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

    /// 取最新一帧，无帧返回 nil。
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
