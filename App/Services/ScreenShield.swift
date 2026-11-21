import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Schermafbeeldingen en schermopnames van een code blokkeren. De code staat in dezelfde beveiligde laag die iOS voor
/// wachtwoordvelden gebruikt: in een screenshot, schermopname, AirPlay of QuickTime is die laag leeg (zwart).
/// Er is geen officiële API voor; werkt de truc in een toekomstige iOS-versie niet meer, dan blijft de code gewoon
/// zichtbaar (geen crash). Tijdens opnemen of spiegelen verbergt Pasr de code daarnaast zelf (officiële melding).
/// Altijd aan voor tijdelijk gedeelde kaarten; voor eigen kaarten met de instelling `settingKey`.
enum ScreenShield {
    static let settingKey = "pasr.screenshotShield"

    /// Voor `.environment(\.codeShield, …)` bovenaan de app.
    static let wrapper: (AnyView) -> AnyView = { AnyView(ShieldedCode(content: $0)) }
}

private struct ShieldedCode: View {
    let content: AnyView
    @State private var captured = false

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            SecureLayer(content: content)
                .opacity(captured ? 0 : 1)
            #else
            content
            #endif
            if captured {
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash.fill").font(.title3)
                    Text("Code verborgen tijdens opnemen").font(.system(.caption, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(.black.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        #if canImport(UIKit)
        .onAppear { captured = Self.isCaptured }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            captured = Self.isCaptured
        }
        #endif
    }

    #if canImport(UIKit)
    private static var isCaptured: Bool {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.contains { $0.isCaptured }
    }
    #endif
}

#if canImport(UIKit)
/// Zet SwiftUI-inhoud in het "canvas" van een beveiligd UITextField.
private struct SecureLayer: UIViewRepresentable {
    let content: AnyView

    final class Coordinator {
        let field = UITextField()
        var host: UIHostingController<AnyView>?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.host = host

        let field = context.coordinator.field
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        // Het canvas waarin iOS de tekst van een wachtwoordveld tekent; niet gevonden = zonder bescherming tonen.
        let canvas = (field.layer.sublayers?.first?.delegate as? UIView)
            ?? field.subviews.first { String(describing: type(of: $0)).contains("Canvas") }
        let target: UIView
        if let canvas {
            canvas.subviews.forEach { $0.removeFromSuperview() }
            canvas.translatesAutoresizingMaskIntoConstraints = false
            canvas.isUserInteractionEnabled = false
            container.addSubview(canvas)
            pin(canvas, to: container)
            target = canvas
        } else {
            target = container
        }
        target.addSubview(host.view)
        pin(host.view, to: target)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.host?.rootView = content
    }

    private func pin(_ view: UIView, to parent: UIView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            view.topAnchor.constraint(equalTo: parent.topAnchor),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}
#endif
