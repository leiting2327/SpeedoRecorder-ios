import Foundation
import AVFoundation
import Combine

/// 麦克风环境音采集：把实时音频样本转发给 VideoRecorder 合进视频。
/// 会话操作走串行队列，权限不可用或设备缺失时安全降级。
final class MicCapture: NSObject, ObservableObject {

    @Published var isAuthorized: Bool = false

    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private weak var recorder: VideoRecorder?
    private let queue = DispatchQueue(label: "mic.capture", qos: .userInitiated)

    func attach(recorder: VideoRecorder) {
        self.recorder = recorder
    }

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                }
                if granted { self?.startSession() }
            }
        default:
            DispatchQueue.main.async { self.isAuthorized = false }
        }
    }

    private func startSession() {
        queue.async { [weak self] in
            guard let self else { return }
            let session = AVCaptureSession()
            session.sessionPreset = .medium

            guard let device = AVCaptureDevice.default(for: .audio),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            if session.canAddInput(input) { session.addInput(input) }

            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: self.queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            self.audioOutput = output

            self.captureSession = session
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.captureSession?.stopRunning()
            self.captureSession = nil
            self.audioOutput = nil
        }
    }
}

extension MicCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        recorder?.appendAudio(sampleBuffer)
    }
}
