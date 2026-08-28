import AVFoundation
import QuartzCore
import UIKit

/// Live AVCaptureMetadataOutput catcher. EAN/UPC and QR, same path as MacroDock / ByteBite.
/// AVCaptureSession is confined to `sessionQueue`; that is the Sendable guarantee.
final class CombVisionCatcher: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "mhv.meta.session")
    private let output = AVCaptureMetadataOutput()
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
        guard session.inputs.isEmpty else {
            Task { @MainActor in
                self.publishPreview()
            }
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: sessionQueue)
            let wanted: [AVMetadataObject.ObjectType] = [.ean8, .ean13, .upce, .qr]
            output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
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

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let payload = first.stringValue,
              !payload.isEmpty
        else { return }
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
