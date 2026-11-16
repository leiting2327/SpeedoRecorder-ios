import Foundation
import AVFoundation

/// 麦克风环境音采集：把实时音频样本转发给 VideoRecorder 合进视频。
final class MicCapture: NSObject {

    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private weak var recorder: VideoRecorder?
    private let queue = DispatchQueue(label: "mic.capture")

    func attach(recorder: VideoRecorder) {
        self.recorder = recorder
    }

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted { self?.startSession() }
            }
        default:
            break
        }
    }

    private func startSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        audioOutput = output

        captureSession = session
        session.startRunning()
    }

    func stop() {
        captureSession?.stopRunning()
        captureSession = nil
    }
}

extension MicCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        recorder?.appendAudio(sampleBuffer)
    }
}
