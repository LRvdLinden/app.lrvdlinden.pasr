import SwiftUI
import AVFoundation
import Vision

/// Live QR- en barcodescanner op de Mac: de ingebouwde camera, een USB-camera of de iPhone als Continuity-camera,
/// met Vision voor QR, Aztec, Code 128 en EAN-13. Zelfde gedrag als de scanner op iOS: elke gelezen code één keer
/// melden, dezelfde code pas na 4 seconden opnieuw.
struct QRScanner: NSViewRepresentable {
    var paused: Bool
    var onCode: (String) -> Void

    /// Is er een camera? (Continuity-camera telt mee zodra de iPhone in de buurt is.)
    static var isAvailable: Bool { CameraSession.defaultDevice() != nil }

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        let coordinator = context.coordinator
        view.session = coordinator.camera.session
        coordinator.camera.onCode = { [weak coordinator] code in coordinator?.consider(code) }
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        context.coordinator.onCode = onCode
        context.coordinator.paused = paused
        if paused { context.coordinator.camera.stop() } else { context.coordinator.camera.start() }
    }

    static func dismantleNSView(_ view: PreviewView, coordinator: Coordinator) {
        coordinator.camera.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator {
        var onCode: (String) -> Void
        var paused = false
        let camera = CameraSession()
        private var last = ""
        private var lastAt = Date.distantPast

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func consider(_ raw: String) {
            guard !paused else { return }
            let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // stempelkaart (PZ…), kortingsbon (PC…), ticket of klantenkaart; de scanner deelt de code later in
            guard ScanCode.classify(code) != nil else { return }
            if code == last && Date.now.timeIntervalSince(lastAt) < 4 { return }
            last = code
            lastAt = .now
            onCode(code)
        }
    }

    /// Camerabeeld in een NSView.
    final class PreviewView: NSView {
        private let preview = AVCaptureVideoPreviewLayer()

        var session: AVCaptureSession? {
            get { preview.session }
            set { preview.session = newValue }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            preview.frame = bounds
        }
    }
}

/// AVCaptureSession met een video-uitgang; elk beeld gaat (hoogstens ~6 keer per seconde) door Vision.
final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    /// Op de hoofdthread aangeroepen met de tekst van een gevonden barcode.
    var onCode: (@MainActor (String) -> Void)?

    private let queue = DispatchQueue(label: "app.lrvdlinden.pasrzakelijk.camera")
    private var configured = false
    private var lastFrame = Date.distantPast
    private lazy var request: VNDetectBarcodesRequest = {
        let r = VNDetectBarcodesRequest()
        r.symbologies = [.qr, .aztec, .code128, .ean13]
        return r
    }()

    /// Ingebouwde camera eerst, anders een externe of Continuity-camera.
    static func defaultDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                         mediaType: .video, position: .unspecified)
        return AVCaptureDevice.default(for: .video) ?? discovery.devices.first
    }

    func start() {
        queue.async { [self] in
            if !configured { configure() }
            if configured && !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = Self.defaultDevice(), let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date.now.timeIntervalSince(lastFrame) > 0.15, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = .now
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, options: [:])
        guard (try? handler.perform([request])) != nil,
              let payload = request.results?.compactMap(\.payloadStringValue).first(where: { !$0.isEmpty }) else { return }
        let callback = onCode
        Task { @MainActor in callback?(payload) }
    }
}

/// Zaklamp: Macs hebben er geen.
enum Torch {
    static var isAvailable: Bool { false }
    static func set(_ on: Bool) {}
}
