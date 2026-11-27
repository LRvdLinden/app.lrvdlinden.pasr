#if os(iOS)
import SwiftUI
import VisionKit
import AVFoundation

/// Live QR- en barcodescanner (VisionKit: QR, Code 128, EAN-13). Meldt elke gelezen code; dezelfde code pas na 4 seconden opnieuw.
struct QRScanner: UIViewControllerRepresentable {
    var paused: Bool
    var onCode: (String) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr, .aztec, .code128, .ean13])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        context.coordinator.paused = paused
        if paused {
            if controller.isScanning { controller.stopScanning() }
        } else if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        var paused = false
        private var last = ""
        private var lastAt = Date.distantPast

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            consider(items)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate items: [RecognizedItem], allItems: [RecognizedItem]) {
            consider(items)
        }

        private func consider(_ items: [RecognizedItem]) {
            guard !paused else { return }
            for item in items {
                // stempelkaart (PZ…), kortingsbon (PC…), ticket of klantenkaart; de scanner deelt de code later in
                guard case .barcode(let barcode) = item,
                      let code = barcode.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      ScanCode.classify(code) != nil else { continue }
                if code == last && Date.now.timeIntervalSince(lastAt) < 4 { return }
                last = code
                lastAt = .now
                onCode(code)
                return
            }
        }
    }
}

/// Zaklamp aan/uit.
enum Torch {
    static var isAvailable: Bool { AVCaptureDevice.default(for: .video)?.hasTorch ?? false }

    static func set(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        if on { try? device.setTorchModeOn(level: 0.8) } else { device.torchMode = .off }
        device.unlockForConfiguration()
    }
}
#endif
