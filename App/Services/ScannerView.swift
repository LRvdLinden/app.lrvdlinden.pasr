import SwiftUI

#if os(iOS)
import VisionKit
import Vision
import AVFoundation

/// Bediening van de scanner van buitenaf: zoom en zaklamp.
@MainActor
final class ScannerControl: ObservableObject {
    weak var controller: DataScannerViewController?
    @Published var torchOn = false
    @Published var zoom: Double = 1

    var hasTorch: Bool { AVCaptureDevice.default(for: .video)?.hasTorch ?? false }

    func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        if on { try? device.setTorchModeOn(level: 0.8) } else { device.torchMode = .off }
        device.unlockForConfiguration()
        torchOn = on
    }

    func setZoom(_ factor: Double) {
        guard let controller else { return }
        let clamped = min(max(factor, controller.minZoomFactor), min(controller.maxZoomFactor, 6))
        controller.zoomFactor = clamped
        zoom = clamped
    }
}

/// Live camera scanner. Calls `onScan` once, als dezelfde code in twee beelden is gelezen (of één keer en daarna een
/// halve seconde niets anders): zo komt er bij glans of schuin houden geen half gelezen code door. Alle soorten codes.
struct ScannerView: UIViewControllerRepresentable {
    var control: ScannerControl? = nil
    var onScan: (String, BarcodeFormat) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        control?.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning { try? controller.startScanning() }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch, device.torchMode == .on,
           (try? device.lockForConfiguration()) != nil {
            device.torchMode = .off
            device.unlockForConfiguration()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String, BarcodeFormat) -> Void
        private var done = false
        private var seen: [String: Int] = [:]
        private var pending: DispatchWorkItem?

        init(onScan: @escaping (String, BarcodeFormat) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            consider(items)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate items: [RecognizedItem], allItems: [RecognizedItem]) {
            consider(items)
        }

        private func consider(_ items: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue, !payload.isEmpty else { continue }
                let format = ImageCodeReader.format(for: barcode.observation.symbology, payload: payload)
                let key = "\(format.rawValue)|\(payload)"
                seen[key, default: 0] += 1
                pending?.cancel()
                if seen[key, default: 0] >= 2 || format.isLinear == false {
                    finish(payload, format)   // 2D-codes hebben een eigen foutcorrectie
                } else {
                    let work = DispatchWorkItem { [weak self] in self?.finish(payload, format) }
                    pending = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                }
                return
            }
        }

        private func finish(_ payload: String, _ format: BarcodeFormat) {
            guard !done else { return }
            done = true
            pending?.cancel()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onScan(payload, format)
        }
    }
}

/// The scanner in a sheet with a viewfinder frame and a cancel button.
struct ScannerSheet: View {
    var onScan: (String, BarcodeFormat) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var control = ScannerControl()

    var body: some View {
        NavigationStack {
            Group {
                if ScannerView.isAvailable {
                    ScannerView(control: control) { value, format in
                        onScan(value, format)
                        dismiss()
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 14) {
                            ScannerControls(control: control)
                            Text("Richt de camera op de barcode. Glimt hij? Houd de kaart iets schuin of zet de zaklamp aan.")
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .pasrGlass()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                } else {
                    ContentUnavailableView("Camera niet beschikbaar",
                                           systemImage: "camera.metering.unknown",
                                           description: Text("Geef toegang tot de camera in Instellingen, of kies een foto van de kaart."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", systemImage: "xmark") { dismiss() } }
            }
        }
    }
}
/// Zoom (1×, 2×, 3×) en zaklamp onder in beeld.
struct ScannerControls: View {
    @ObservedObject var control: ScannerControl

    var body: some View {
        HStack(spacing: 10) {
            ForEach([1.0, 2.0, 3.0], id: \.self) { factor in
                Button { control.setZoom(factor) } label: {
                    Text("\(Int(factor))×")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(minWidth: 36, minHeight: 30)
                }
                .pasrGlassButton(prominent: abs(control.zoom - factor) < 0.25)
                .accessibilityLabel(Text("Zoom \(Int(factor)) keer"))
            }
            if control.hasTorch {
                Button { control.setTorch(!control.torchOn) } label: {
                    Image(systemName: control.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 36, minHeight: 30)
                }
                .pasrGlassButton(prominent: control.torchOn)
                .accessibilityLabel(Text(control.torchOn ? "Zaklamp uit" : "Zaklamp aan"))
            }
        }
    }
}
#endif
