import AVFoundation
import QuartzCore
import UIKit
import Vision

/// Live Vision barcode catcher. VNDetectBarcodesRequest runs on each video buffer.
/// AVCaptureSession is confined to `sessionQueue`; that is the Sendable guarantee.
final class CombVisionCatcher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "mhv.vision.session")
    private let output = AVCaptureVideoDataOutput()
    private var lastPayload = ""
    private var lastStamp: TimeInterval = 0
    private let debounce: TimeInterval = 1.7

    var onCode: (@MainActor (String) -> Void)?
    var onPreview: (@MainActor (AVCaptureVideoPreviewLayer) -> Void)?

    static var hasCaptureDevice: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    static var authorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func prepare() {
        sessionQueue.async { [weak self] in
            self?.configure()
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
        Task { @MainActor in
            self.publishPreview()
        }
    }

    @MainActor
    private func publishPreview() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        onPreview?(layer)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.ean8, .ean13, .upce, .qr]
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }
        guard let payload = request.results?
            .compactMap(\.payloadStringValue)
            .first(where: { !$0.isEmpty }) else { return }
        let now = CACurrentMediaTime()
        if payload == lastPayload, now - lastStamp < debounce { return }
        if now - lastStamp < debounce { return }
        lastPayload = payload
        lastStamp = now
        let code = onCode
        Task { @MainActor in
            code?(payload)
        }
    }
}
